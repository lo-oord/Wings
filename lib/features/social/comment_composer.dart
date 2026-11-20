import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../data/models/sticker_catalog.dart';
import '../stickers/comment_draft.dart';
import '../stickers/sticker_providers.dart';
import '../stickers/sticker_sheet.dart';
import '../stickers/sticker_view.dart';

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
  });

  final TextEditingController controller;

  /// True while the parent is sending a comment.
  final bool sending;

  /// Returns true when the comment was actually written.
  final Future<bool> Function(String text, String? stickerId) onSend;

  final int maxLength;

  @override
  ConsumerState<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends ConsumerState<CommentComposer> {
  Sticker? _sticker;
  bool _submitting = false;

  bool get _busy => _submitting || widget.sending;

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
      );
      if (!mounted || !sent) return;
      widget.controller.clear();
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              WingsIconButton(
                icon: Icons.emoji_emotions_outlined,
                tooltip: Tr.of(context, ar: 'الملصقات', en: 'Stickers'),
                onPressed: _busy ? null : _pickSticker,
                color: selected == null
                    ? palette.textSecondary
                    : palette.primary,
              ),
              const SizedBox(width: Space.xxs),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: widget.maxLength,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) => setState(() {}),
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
