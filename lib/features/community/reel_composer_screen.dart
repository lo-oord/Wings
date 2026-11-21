import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
import '../../data/models/anime.dart';
import '../../data/models/community.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/community_repository.dart';
import 'community_video.dart';
import 'photo_editor_screen.dart';
import 'suggestion_panel.dart';

/// A publishing studio that is deliberately different from the community
/// composer: a full-bleed vertical preview, the caption and sound underneath,
/// and the Reel-only choices (cover, category, comments, downloads, reposts)
/// grouped where the thumb already is.
///
/// The document is written only after the video and its cover reached Tigris,
/// and a failed save removes the objects it uploaded, so Reels can never point
/// at half-uploaded media.
class ReelComposerScreen extends ConsumerStatefulWidget {
  const ReelComposerScreen({super.key, this.seed});

  /// A sound taken from another Reel («استخدام هذا الصوت») or any pre-filled
  /// studio state. The member still chooses their own video or pictures.
  final ReelComposerSeed? seed;

  @override
  ConsumerState<ReelComposerScreen> createState() => _ReelComposerScreenState();
}

class _ReelComposerScreenState extends ConsumerState<ReelComposerScreen> {
  final TextEditingController _caption = TextEditingController();
  final TextEditingController _sound = TextEditingController();

  final List<MentionRef> _mentions = <MentionRef>[];
  final List<AnimeRef> _animeRefs = <AnimeRef>[];

  _VideoDraft? _video;
  _DraftImage? _cover;

  /// A picture Reel: each frame stays [_frameMs] on screen.
  final List<_DraftImage> _frames = <_DraftImage>[];
  final List<int> _frameDurationsMs = <int>[];
  int _frameMs = 2500;
  int _activeFrame = 0;
  _SoundDraft? _soundFile;
  String? _soundKey;
  String _soundAuthorUid = '';
  String? _uploadedSoundKey;

  String _category = '';
  bool _allowComments = true;
  bool _allowDownload = true;
  bool _allowRepost = true;

  bool _publishing = false;
  String? _stage;
  double? _progress;
  String? _failure;

  String? _uploadedVideoKey;
  String? _uploadedCoverKey;

  Timer? _debounce;
  ActiveTrigger? _trigger;

  static const List<String> _categoryOptions = <String>[
    'ترفيه',
    'أنمي',
    'تحدي',
    'موسيقى',
    'تعليم',
    'رياضة',
  ];

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed != null) {
      _sound.text = seed.title;
      _soundKey = seed.key.isEmpty ? null : seed.key;
      _soundAuthorUid = seed.authorUid;
      if (seed.text.isNotEmpty) _caption.text = seed.text;
    }
    _caption.addListener(_onCaptionChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _caption.removeListener(_onCaptionChanged);
    _caption.dispose();
    _sound.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      (_video != null || _frames.isNotEmpty) && !_publishing;

  void _onCaptionChanged() {
    final trigger = detectTrigger(_caption);
    if (trigger == null) {
      _debounce?.cancel();
      if (_trigger != null) setState(() => _trigger = null);
      setState(() {});
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _trigger = trigger);
    });
    setState(() {});
  }

  void _pickMention(UserProfile user) {
    final trigger = _trigger;
    if (trigger == null) return;
    applySuggestion(_caption, trigger, '@${user.username}');
    if (!_mentions.any((item) => item.uid == user.uid)) {
      _mentions.add(MentionRef(uid: user.uid, username: user.username));
    }
    setState(() => _trigger = null);
  }

  void _pickAnime(Anime anime) {
    final trigger = _trigger;
    if (trigger == null) return;
    applySuggestion(_caption, trigger, '#${anime.title}');
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            context.isRtl
                ? Icons.arrow_forward_rounded
                : Icons.arrow_back_rounded,
          ),
          onPressed: _publishing
              ? null
              : () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          Tr.of(context, ar: 'استوديو الريلز', en: 'Reels studio'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(end: Space.sm),
            child: FilledButton(
              onPressed: _canPublish ? _publish : null,
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
              ),
              child: _publishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      Tr.of(context, ar: 'نشر', en: 'Publish'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _preview()),
          Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.46,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF101014),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(Radii.xl),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                Space.xl,
              ),
              children: <Widget>[
                _captionField(),
                if (_trigger != null)
                  SuggestionPanel(
                    trigger: _trigger!,
                    onPickUser: _pickMention,
                    onPickAnime: _pickAnime,
                  ),
                if (_mentions.isNotEmpty || _animeRefs.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final mention in _mentions)
                        _chip('@${mention.username}', () {
                          setState(() => _mentions.remove(mention));
                        }),
                      for (final anime in _animeRefs)
                        _chip('#${anime.title}', () {
                          setState(() => _animeRefs.remove(anime));
                        }),
                    ],
                  ),
                ],
                const SizedBox(height: Space.sm),
                _soundField(),
                const SizedBox(height: Space.md),
                _categoryChips(),
                const SizedBox(height: Space.md),
                _settings(),
                if (_stage != null) ...<Widget>[
                  const SizedBox(height: Space.md),
                  Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          _stage!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_progress != null) ...<Widget>[
                    const SizedBox(height: Space.xs),
                    LinearProgressIndicator(value: _progress, minHeight: 3),
                  ],
                ],
                if (_failure != null) ...<Widget>[
                  const SizedBox(height: Space.md),
                  Container(
                    padding: const EdgeInsets.all(Space.sm),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.error_outline_rounded,
                          size: 16,
                          color: palette.danger,
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(
                            _failure!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              height: 1.5,
                            ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    final video = _video;
    if (video == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.movie_creation_outlined,
              color: Colors.white.withValues(alpha: 0.55),
              size: 42,
            ),
            const SizedBox(height: Space.md),
            Text(
              Tr.of(
                context,
                ar: 'اختر مقطعًا عموديًا لتبدأ',
                en: 'Pick a vertical clip to start',
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: Space.md),
            FilledButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_library_outlined, size: 18),
              label: Text(
                Tr.of(context, ar: 'اختيار فيديو', en: 'Pick a video'),
              ),
            ),
            const SizedBox(height: Space.xs),
            TextButton(
              onPressed: () => _pickVideo(camera: true),
              child: Text(
                Tr.of(context, ar: 'تصوير مقطع', en: 'Record a clip'),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
            const SizedBox(height: Space.xs),
            OutlinedButton.icon(
              onPressed: _publishing ? null : _pickFrames,
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: Text(
                Tr.of(context, ar: 'صور كريل', en: 'Picture Reel'),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }
    if (_frames.isNotEmpty) return _framesPreview();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: CommunityVideo(
            localPath: video.file.path,
            aspectRatio: video.aspect,
            startMuted: true,
            loop: true,
            fit: BoxFit.contain,
            showChrome: false,
          ),
        ),
        PositionedDirectional(
          top: Space.sm,
          start: Space.sm,
          child: _overlayButton(
            icon: Icons.swap_horiz_rounded,
            label: Tr.of(context, ar: 'تغيير', en: 'Replace'),
            onTap: _publishing ? null : _pickVideo,
          ),
        ),
        PositionedDirectional(
          top: Space.sm,
          end: Space.sm,
          child: _overlayButton(
            icon: _cover == null
                ? Icons.image_outlined
                : Icons.check_circle_outline_rounded,
            label: _cover == null
                ? Tr.of(context, ar: 'غلاف', en: 'Cover')
                : Tr.of(context, ar: 'تم', en: 'Cover set'),
            onTap: _publishing ? null : _pickCover,
          ),
        ),
        PositionedDirectional(
          start: Space.sm,
          end: Space.sm,
          bottom: Space.sm,
          child: Row(
            children: <Widget>[
              Text(
                video.label,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
              const Spacer(),
              Text(
                Tr.of(
                  context,
                  ar: '٥ دقائق كحد أقصى · ٩٠ ميجابايت',
                  en: 'Up to 5 min · 90 MB',
                ),
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickFrames() async {
    if (_publishing) return;
    try {
      final picked = await ImagePicker().pickMultiImage(
        maxWidth: 1080,
        imageQuality: 88,
      );
      if (picked.isEmpty || !mounted) return;
      final remaining = CommunityRepository.maxReelFrames - _frames.length;
      if (remaining <= 0) {
        context.showSnack(
          Tr.of(
            context,
            ar: 'يمكن إضافة ١٠ صور كحد أقصى للريل.',
            en: 'A reel can hold up to 10 pictures.',
          ),
          isError: true,
        );
        return;
      }
      final frames = <_DraftImage>[];
      for (final file in picked.take(remaining)) {
        frames.add(
          _DraftImage(bytes: await file.readAsBytes(), file: File(file.path)),
        );
      }
      if (!mounted) return;
      setState(() {
        _frames.addAll(frames);
        _frameDurationsMs.addAll(List<int>.filled(frames.length, _frameMs));
        _activeFrame = _frames.length - 1;
        _video = null;
      });
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _pickSound() async {
    if (_publishing) return;
    try {
      final file = await FilePicker.pickFile(type: FileType.audio);
      final path = file?.path;
      if (file == null || path == null || !mounted) return;
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      if (bytes.length > CommunityMediaService.maxAudioBytes) {
        context.showSnack(
          Tr.of(
            context,
            ar: 'حجم الصوت أكبر من ١٢ ميجابايت.',
            en: 'The sound is larger than 12 MB.',
          ),
          isError: true,
        );
        return;
      }
      final extension = (file.extension ?? 'mp3').toLowerCase();
      final contentType = switch (extension) {
        'wav' => 'audio/wav',
        'm4a' || 'mp4' => 'audio/mp4',
        'ogg' => 'audio/ogg',
        _ => 'audio/mpeg',
      };
      setState(() {
        _soundFile = _SoundDraft(
          bytes: bytes,
          extension: extension,
          contentType: contentType,
        );
        if (_sound.text.trim().isEmpty) {
          _sound.text = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
        }
        _uploadedSoundKey = null;
      });
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Widget _framesPreview() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (_frames.isNotEmpty)
          Image.memory(_frames.first.bytes, fit: BoxFit.contain),
        PositionedDirectional(
          top: Space.sm,
          start: Space.sm,
          child: _overlayButton(
            icon: Icons.add_photo_alternate_outlined,
            label: Tr.of(
              context,
              ar: 'إضافة صور (${_frames.length}/10)',
              en: 'Add pictures (${_frames.length}/10)',
            ),
            onTap: _publishing ? null : _pickFrames,
          ),
        ),
        PositionedDirectional(
          top: Space.sm,
          end: Space.sm,
          child: _overlayButton(
            icon: Icons.delete_outline_rounded,
            label: Tr.of(context, ar: 'مسح', en: 'Clear'),
            onTap: _publishing
                ? null
                : () => setState(() {
                    _frames.clear();
                    _frameDurationsMs.clear();
                    _activeFrame = 0;
                    _cover = null;
                  }),
          ),
        ),
        PositionedDirectional(
          start: Space.md,
          end: Space.md,
          bottom: Space.sm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    Tr.of(
                      context,
                      ar:
                          'مدة الصورة ${_activeFrame + 1}: '
                          '${((_frameDurationsMs.isEmpty ? _frameMs : _frameDurationsMs[_activeFrame.clamp(0, _frameDurationsMs.length - 1)]) / 1000).toStringAsFixed(1)} ث',
                      en:
                          'Picture ${_activeFrame + 1}: '
                          '${((_frameDurationsMs.isEmpty ? _frameMs : _frameDurationsMs[_activeFrame.clamp(0, _frameDurationsMs.length - 1)]) / 1000).toStringAsFixed(1)}s',
                    ),
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    Tr.of(
                      context,
                      ar: 'اضغط صورة لاختيارها، واضغط مطولًا لتعديلها',
                      en: 'Tap a picture to select it, long-press to edit',
                    ),
                    style: const TextStyle(color: Colors.white38, fontSize: 8),
                  ),
                ],
              ),
              Slider(
                value:
                    (_frameDurationsMs.isEmpty
                            ? _frameMs
                            : _frameDurationsMs[_activeFrame.clamp(
                                0,
                                _frameDurationsMs.length - 1,
                              )])
                        .toDouble(),
                min: 1000,
                max: 5000,
                divisions: 8,
                onChanged: _publishing
                    ? null
                    : (value) => setState(() {
                        if (_frameDurationsMs.isEmpty) {
                          _frameMs = value.round();
                          return;
                        }
                        _frameDurationsMs[_activeFrame.clamp(
                          0,
                          _frameDurationsMs.length - 1,
                        )] = value
                            .round();
                      }),
              ),
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _frames.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) => GestureDetector(
                    onTap: _publishing
                        ? null
                        : () => setState(() => _activeFrame = index),
                    onLongPress: _publishing ? null : () => _editFrame(index),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.xs),
                        border: Border.all(
                          color: _activeFrame == index
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.xs),
                        child: Stack(
                          children: <Widget>[
                            Image.memory(
                              _frames[index].bytes,
                              width: 42,
                              height: 54,
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                color: Colors.black54,
                                padding: const EdgeInsets.all(2),
                                child: Text(
                                  '${((index < _frameDurationsMs.length ? _frameDurationsMs[index] : _frameMs) / 1000).toStringAsFixed(1)}s',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editFrame(int index) async {
    final edited = await openPhotoEditor(context, bytes: _frames[index].bytes);
    if (edited == null || !mounted) return;
    setState(() {
      _frames[index] = _DraftImage(bytes: edited.bytes, file: edited.file);
      _uploadedCoverKey = null;
    });
  }

  Widget _overlayButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: 5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _captionField() {
    return TextField(
      controller: _caption,
      enabled: !_publishing,
      minLines: 1,
      maxLines: 4,
      maxLength: 2000,
      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
      decoration: InputDecoration(
        hintText: Tr.of(
          context,
          ar: 'اكتب وصفًا للريل… @ لذكر مستخدم و# لأنمي',
          en: 'Describe your reel… @ to mention, # for an anime',
        ),
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        border: InputBorder.none,
        counterStyle: const TextStyle(color: Colors.white30, fontSize: 9),
      ),
    );
  }

  Widget _soundField() {
    return TextField(
      controller: _sound,
      enabled: !_publishing,
      maxLength: 80,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.music_note_rounded,
          size: 17,
          color: Colors.white54,
        ),
        suffixIcon: IconButton(
          tooltip: Tr.of(context, ar: 'اختيار صوت', en: 'Pick a sound'),
          icon: Icon(
            _soundFile == null
                ? Icons.library_music_outlined
                : Icons.check_circle_outline_rounded,
            size: 18,
            color: Colors.white54,
          ),
          onPressed: _publishing ? null : _pickSound,
        ),
        hintText: Tr.of(
          context,
          ar: 'اسم الصوت أو الموسيقى (اختياري)',
          en: 'Sound or music name (optional)',
        ),
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: Space.sm),
        counterStyle: const TextStyle(color: Colors.white30, fontSize: 9),
      ),
    );
  }

  Widget _categoryChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final category in _categoryOptions)
          ChoiceChip(
            label: Text(category),
            selected: _category == category,
            onSelected: _publishing
                ? null
                : (selected) =>
                      setState(() => _category = selected ? category : ''),
            labelStyle: TextStyle(
              fontSize: 10,
              color: _category == category ? Colors.black : Colors.white70,
            ),
            backgroundColor: Colors.white10,
            selectedColor: context.palette.primary,
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _settings() {
    Widget toggle({
      required IconData icon,
      required String label,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) => InkWell(
      onTap: _publishing ? null : () => onChanged(!value),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 7),
        decoration: BoxDecoration(
          color: value ? Colors.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: value ? Colors.white24 : Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: value ? Colors.white : Colors.white38),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: value ? Colors.white : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        toggle(
          icon: Icons.mode_comment_outlined,
          label: Tr.of(context, ar: 'التعليقات', en: 'Comments'),
          value: _allowComments,
          onChanged: (value) => setState(() => _allowComments = value),
        ),
        toggle(
          icon: Icons.download_outlined,
          label: Tr.of(context, ar: 'التنزيل', en: 'Downloads'),
          value: _allowDownload,
          onChanged: (value) => setState(() => _allowDownload = value),
        ),
        toggle(
          icon: Icons.repeat_rounded,
          label: Tr.of(context, ar: 'إعادة النشر', en: 'Reposts'),
          value: _allowRepost,
          onChanged: (value) => setState(() => _allowRepost = value),
        ),
      ],
    );
  }

  Widget _chip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          InkWell(
            onTap: _publishing ? null : onRemove,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 12, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickVideo({bool camera = false}) async {
    if (_publishing) return;
    try {
      final picked = await ImagePicker().pickVideo(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(
          seconds: CommunityMediaService.maxReelSeconds,
        ),
      );
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      if (!file.existsSync()) {
        throw const MediaRejectedException('missing-file');
      }
      final length = await file.length();
      if (length <= 0 || length > CommunityMediaService.maxReelBytes) {
        if (mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'حجم الفيديو أكبر من ٩٠ ميجابايت. اختر مقطعًا أقصر أو أخف.',
              en: 'This video is larger than 90 MB. Pick a shorter or lighter clip.',
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
            ar: 'تعذّر قراءة هذا الفيديو. جرّب MP4.',
            en: 'This video could not be read. Try an MP4 file.',
          ),
          isError: true,
        );
        return;
      }
      if (probe.duration >
          const Duration(seconds: CommunityMediaService.maxReelSeconds)) {
        context.showSnack(
          Tr.of(
            context,
            ar: 'مدة الريل تتجاوز ٥ دقائق.',
            en: 'The reel is longer than 5 minutes.',
          ),
          isError: true,
        );
        return;
      }
      setState(() {
        _video = _VideoDraft(
          file: file,
          durationMs: probe.duration.inMilliseconds,
          width: probe.width,
          height: probe.height,
        );
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
      return _Probe(
        duration: duration,
        width: player.state.width ?? 0,
        height: player.state.height ?? 0,
      );
    } on Object {
      return null;
    } finally {
      unawaited(player.dispose());
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
      final bytes = await FlutterImageCompress.compressWithFile(
        picked.path,
        minWidth: 900,
        minHeight: 900,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      if (bytes == null || !mounted) return;
      setState(() {
        _cover = _DraftImage(bytes: bytes, file: File(picked.path));
        _uploadedCoverKey = null;
      });
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _publish() async {
    if (_publishing) return;
    var profile = ref.read(profileProvider);
    final uid = ref.read(authProvider)?.id;
    final video = _video;
    if (uid == null) {
      context.showSnack(
        Tr.of(context, ar: 'سجّل الدخول أولًا.', en: 'Sign in first.'),
        isError: true,
      );
      return;
    }
    // `authProvider` is published before the profile finishes loading, so a
    // null profile here is not a signed-out session. Reload it once, then tell
    // the member the real problem if it is still missing.
    if (profile == null) {
      await ref.read(profileProvider.notifier).reload();
      if (!mounted) return;
      profile = ref.read(profileProvider);
    }
    if (profile == null) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'أكمل ملفك الشخصي قبل نشر الريل.',
          en: 'Complete your profile before publishing a reel.',
        ),
        isError: true,
      );
      return;
    }
    if (video == null && _frames.isEmpty) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'اختر فيديو أو صورًا للريل أولًا.',
          en: 'Pick a reel video or pictures first.',
        ),
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
      _stage = Tr.of(
        context,
        ar: 'جارٍ تجهيز الفيديو…',
        en: 'Preparing the video…',
      );
    });

    try {
      var soundKey = _uploadedSoundKey ?? _soundKey;
      final sound = _soundFile;
      if (soundKey == null && sound != null) {
        final uploads = await media.createUploads(
          postId: postId,
          files: <MediaFile>[
            MediaFile(
              bytes: Uint8List(0),
              contentType: sound.contentType,
              extension: sound.extension,
              declaredSize: sound.bytes.length,
            ),
          ],
        );
        await media.upload(uploads.first, sound.bytes);
        soundKey = uploads.first.key;
        _uploadedSoundKey = soundKey;
        uploaded.add(soundKey);
      }

      // Picture Reels upload their frames instead of a video and never create
      // a second copy of the sound when it came from another Reel.
      if (video == null) {
        setState(() {
          _stage = Tr.of(
            context,
            ar: 'جارٍ رفع الصور…',
            en: 'Uploading the pictures…',
          );
          _progress = null;
        });
        final uploads = await media.createUploads(
          postId: postId,
          files: <MediaFile>[
            for (final frame in _frames)
              MediaFile(
                bytes: frame.bytes,
                contentType: 'image/jpeg',
                extension: 'jpg',
              ),
          ],
        );
        final keys = <String>[];
        for (var index = 0; index < uploads.length; index++) {
          await media.upload(uploads[index], _frames[index].bytes);
          keys.add(uploads[index].key);
          uploaded.add(uploads[index].key);
        }
        if (!mounted) return;
        final id = await repo.createPost(
          author: profile,
          text: _caption.text,
          id: postId,
          kind: PostKind.reel,
          videoThumbnailKey: keys.isEmpty ? null : keys.first,
          reelFrames: <ReelFrame>[
            for (var index = 0; index < keys.length; index++)
              ReelFrame(
                key: keys[index],
                durationMs: index < _frameDurationsMs.length
                    ? _frameDurationsMs[index]
                    : _frameMs,
              ),
          ],
          mentions: List<MentionRef>.unmodifiable(_mentions),
          animeRefs: List<AnimeRef>.unmodifiable(_animeRefs),
          allowComments: _allowComments,
          allowDownload: _allowDownload,
          allowRepost: _allowRepost,
          category: _category,
          soundTitle: _sound.text.trim(),
          soundKey: soundKey ?? '',
          soundAuthorUid: _soundAuthorUid,
        );
        final post = await repo.fetchPost(id);
        if (!mounted) return;
        Navigator.of(context).pop(post);
        return;
      }

      final extension = video.file.path.toLowerCase().endsWith('.mov')
          ? 'mov'
          : 'mp4';
      var videoKey = _uploadedVideoKey;
      if (videoKey == null) {
        final uploads = await media.createUploads(
          postId: postId,
          files: <MediaFile>[
            MediaFile(
              bytes: Uint8List(0),
              contentType: extension == 'mov' ? 'video/quicktime' : 'video/mp4',
              extension: extension,
              declaredSize: await video.file.length(),
            ),
          ],
        );
        final bytes = await video.file.readAsBytes();
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

      var coverKey = _uploadedCoverKey;
      if (coverKey == null && _cover != null) {
        setState(() {
          _stage = Tr.of(
            context,
            ar: 'جارٍ رفع الغلاف…',
            en: 'Uploading cover…',
          );
          _progress = null;
        });
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
        text: _caption.text,
        id: postId,
        kind: PostKind.reel,
        videoKey: videoKey,
        videoThumbnailKey: coverKey,
        videoDurationMs: video.durationMs,
        videoWidth: video.width,
        videoHeight: video.height,
        mentions: List<MentionRef>.unmodifiable(_mentions),
        animeRefs: List<AnimeRef>.unmodifiable(_animeRefs),
        allowComments: _allowComments,
        allowDownload: _allowDownload,
        allowRepost: _allowRepost,
        category: _category,
        soundTitle: _sound.text.trim(),
        soundKey: soundKey ?? '',
        soundAuthorUid: _soundAuthorUid,
        videoBytes: video.file.lengthSync(),
      );
      final post = await repo.fetchPost(id);
      if (!mounted) return;
      Navigator.of(context).pop(post);
    } on Object catch (error) {
      if (uploaded.isNotEmpty) {
        unawaited(media.deleteObjects(uploaded).catchError((Object _) {}));
        _uploadedVideoKey = null;
        _uploadedCoverKey = null;
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
        ar: 'خدمة رفع الوسائط غير متاحة الآن. تحقق من اتصالك وأعد المحاولة.',
        en: 'Media upload is unavailable right now. Check your connection and retry.',
      );
    }
    if (error is MediaRejectedException) {
      return Tr.of(
        context,
        ar: 'لم يُقبل الملف. تأكد أن الفيديو MP4/MOV حتى ٥٠ ميجابايت و٦٠ ثانية.',
        en: 'The file was rejected. Use an MP4/MOV clip up to 50 MB and 60 seconds.',
      );
    }
    return userFacingError(context, error);
  }
}

class _VideoDraft {
  const _VideoDraft({
    required this.file,
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final File file;
  final int durationMs;
  final int width;
  final int height;

  double get aspect => (width > 0 && height > 0) ? width / height : 9 / 16;

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

/// A sound file chosen from the device, kept in memory until publish.
class _SoundDraft {
  const _SoundDraft({
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final Uint8List bytes;
  final String extension;
  final String contentType;
}

/// What «استخدام هذا الصوت» hands to the studio: the original object key and
/// the credit of the account that first published it.
class ReelComposerSeed {
  const ReelComposerSeed({
    required this.key,
    required this.title,
    required this.authorUid,
    this.text = '',
  });

  final String key;
  final String title;
  final String authorUid;
  final String text;
}
