import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../data/models/sticker_catalog.dart';
import 'sticker_providers.dart';

/// Local sticker artwork. Nothing here touches the network: the asset comes
/// from the app bundle and the decoded bitmap is kept in Flutter's image cache.
class StickerAsset extends StatelessWidget {
  const StickerAsset({super.key, required this.sticker, this.size = 120});

  final Sticker sticker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (size * ratio).clamp(48, 512).round();
    return RepaintBoundary(
      child: Image.asset(
        sticker.assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => _Unavailable(size: size),
      ),
    );
  }
}

/// A sticker inside a comment or a reply.
///
/// Unknown or retired ids never break the thread: the text (when present) is
/// still shown and the sticker slot becomes a small «غير متاح» note. The id
/// stays in Firestore untouched.
class StickerMessage extends ConsumerWidget {
  const StickerMessage({
    super.key,
    required this.stickerId,
    this.size = 132,
    this.compact = false,
  });

  final String stickerId;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(stickerCatalogProvider);
    final catalog = request.value;
    if (catalog == null) {
      // A failed load behaves like an unknown id: the text stays, the sticker
      // slot shows a quiet fallback instead of an endless spinner.
      if (request.hasError) return _Unavailable(size: compact ? 72 : 96);
      // The catalogue is still loading; reserve the space quietly instead of
      // jumping the list when it arrives.
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: context.palette.textMuted,
            ),
          ),
        ),
      );
    }
    final sticker = catalog.byId(stickerId);
    if (sticker == null) {
      return _Unavailable(size: compact ? 72 : 96);
    }
    return Semantics(
      button: true,
      label: Tr.of(
        context,
        ar: 'ملصق ${sticker.name(true)}',
        en: 'Sticker ${sticker.name(false)}',
      ),
      child: GestureDetector(
        onTap: () => showStickerPreview(context, sticker),
        child: StickerAsset(sticker: sticker, size: size),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size * 0.72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.image_not_supported_outlined,
            size: 20,
            color: palette.textMuted,
          ),
          const SizedBox(height: Space.xxs),
          Text(
            Tr.of(context, ar: 'الملصق غير متاح', en: 'Sticker unavailable'),
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(
              color: palette.textMuted,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-size preview of one sticker, opened by tapping it in a comment.
Future<void> showStickerPreview(BuildContext context, Sticker sticker) {
  final arabic = Tr.isArabic(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: Tr.of(context, ar: 'إغلاق', en: 'Close'),
    barrierColor: Colors.black.withValues(alpha: 0.74),
    transitionDuration: Motion.normal,
    pageBuilder: (dialogContext, animation, secondary) {
      final media = MediaQuery.sizeOf(dialogContext);
      final size = media.width < 420 ? media.width * 0.66 : 300.0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: dialogContext.palette.surface,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(color: dialogContext.palette.border),
                  ),
                  child: StickerAsset(sticker: sticker, size: size),
                ),
                const SizedBox(height: Space.sm),
                Text(
                  sticker.name(arabic),
                  textAlign: TextAlign.center,
                  style: dialogContext.text.labelMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: Space.sm),
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text(Tr.of(dialogContext, ar: 'إغلاق', en: 'Close')),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.emphasized,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
