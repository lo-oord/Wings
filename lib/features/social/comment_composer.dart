import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../data/models/anime.dart';
import '../../data/models/community.dart';
import '../../data/models/sticker_catalog.dart';
import '../../data/models/user_profile.dart';
import '../community/suggestion_panel.dart';
import '../stickers/comment_draft.dart';
import '../stickers/sticker_providers.dart';
import '../stickers/sticker_sheet.dart';
import '../stickers/sticker_view.dart';

/// Opens the same mention/hashtag aware composer in a dialog and returns the
/// finished draft, used by reply flows that are not a pinned bottom bar.
Future<CommentDraft?> showCommentComposerDialog(
  BuildContext context, {
  String? title,
}) async {
  final controller = TextEditingController();
  final draft = await showDialog<CommentDraft>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: title == null ? null : Text(title),
      contentPadding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.md,
        Space.md,
        0,
      ),
      content: SizedBox(
        width: 420,
        child: CommentComposer(
          controller: controller,
          sending: false,
          onSend: (text, stickerId, mentions, animeRefs) async {
            final result = CommentDraft(
              text: text,
              stickerId: stickerId,
              mentions: mentions,
              animeRefs: animeRefs,
            );
            if (!result.canSend) return false;
            Navigator.of(dialogContext).pop(result);
            return true;
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
        ),
      ],
    ),
  );
  // The dialog's closing animation still paints the field for a moment.
  Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
  return draft;
}

/// Composer used by the comments page.
///
/// The same field supports the three accepted shapes: text only, sticker only,
/// and text above a sticker. Picking a sticker never sends anything and never
/// touches the text field, so opening or closing the picker cannot lose a
/// draft. The text and the sticker are cleared only after [onSend] succeeds.
class CommentComposer extends ConsumerStatefulWidget {
  const CommentComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.maxLength = 1000,
    this.showStickers = true,
  });

  final TextEditingController controller;

  /// True while the parent is sending a comment.
  final bool sending;

  /// Returns true when the comment was actually written.
  final Future<bool> Function(
    String text,
    String? stickerId,
    List<MentionRef> mentions,
    List<AnimeRef> animeRefs,
  )
  onSend;

  final int maxLength;

  /// Reel comments keep their compact shape but still get `@` and `#`.
  final bool showStickers;

  @override
  ConsumerState<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends ConsumerState<CommentComposer> {
  Sticker? _sticker;
  bool _submitting = false;
  ActiveTrigger? _trigger;
  final List<MentionRef> _mentions = <MentionRef>[];
  final List<AnimeRef> _animeRefs = <AnimeRef>[];

  bool get _busy => _submitting || widget.sending;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final trigger = detectTrigger(widget.controller);
    if (mounted) setState(() => _trigger = trigger);
  }

  void _pickUser(UserProfile user) {
    final trigger = _trigger;
    if (trigger == null) return;
    applySuggestion(widget.controller, trigger, '@${user.username}');
    if (!_mentions.any((item) => item.uid == user.uid)) {
      _mentions.add(MentionRef(uid: user.uid, username: user.username));
    }
    setState(() => _trigger = null);
  }

  void _pickAnime(Anime anime) {
    final trigger = _trigger;
    if (trigger == null) return;
    applySuggestion(widget.controller, trigger, '#${anime.title}');
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

  Future<void> _pickSticker() async {
    final picked = await showStickerPicker(context);
    if (picked == null || !mounted) return;
    setState(() => _sticker = picked);
  }

  Future<void> _submit() async {
    // Guards a double tap that lands before the parent rebuilds with
    // `sending: true`; the button is also disabled while submitting.
    if (_busy) return;
    final draft = CommentDraft(
      text: widget.controller.text,
      stickerId: _sticker?.id,
    );
    if (!draft.canSend) return;
    setState(() => _submitting = true);
    try {
      final sent = await widget.onSend(
        draft.trimmedText,
        draft.normalizedStickerId,
        List<MentionRef>.unmodifiable(_mentions),
        List<AnimeRef>.unmodifiable(_animeRefs),
      );
      if (!mounted || !sent) return;
      widget.controller.clear();
      _mentions.clear();
      _animeRefs.clear();
      final used = _sticker;
      setState(() => _sticker = null);
      if (used != null) {
        await ref.read(stickerLibraryProvider.notifier).markUsed(used.id);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = _sticker;
    final draft = CommentDraft(
      text: widget.controller.text,
      stickerId: selected?.id,
    );
    // The field rebuilds on every keystroke only to keep the send button state
    // honest; the surrounding list is untouched.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.sm,
        Space.md,
        Space.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Space.sm,
                  Space.xs,
                  Space.xs,
                  Space.xs,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: <Widget>[
                    StickerAsset(sticker: selected, size: 34),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        selected.name(Tr.isArabic(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                    WingsIconButton(
                      icon: Icons.close_rounded,
                      size: 32,
                      tooltip: Tr.of(
                        context,
                        ar: 'إزالة الملصق',
                        en: 'Remove sticker',
                      ),
                      onPressed: _busy
                          ? null
                          : () => setState(() => _sticker = null),
                    ),
                  ],
                ),
              ),
            ),
          if (_trigger case final trigger?)
            SuggestionPanel(
              trigger: trigger,
              onPickUser: _pickUser,
              onPickAnime: _pickAnime,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (widget.showStickers) ...<Widget>[
                WingsIconButton(
                  icon: Icons.emoji_emotions_outlined,
                  tooltip: Tr.of(context, ar: 'الملصقات', en: 'Stickers'),
                  onPressed: _busy ? null : _pickSticker,
                  color: selected == null
                      ? palette.textSecondary
                      : palette.primary,
                ),
                const SizedBox(width: Space.xxs),
              ],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: widget.maxLength,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) => _onTextChanged(),
                  decoration: InputDecoration(
                    hintText: Tr.of(
                      context,
                      ar: 'أضف تعليقًا…',
                      en: 'Add a comment…',
                    ),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              WingsIconButton(
                icon: Icons.send_rounded,
                filled: true,
                tooltip: Tr.of(context, ar: 'إرسال', en: 'Send'),
                onPressed: (_busy || !draft.canSend) ? null : _submit,
                color: (_busy || !draft.canSend)
                    ? palette.textMuted
                    : palette.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
