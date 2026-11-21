import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_image.dart';

/// A full-screen picture viewer for a community post.
///
/// Swipe between every picture of the post, zoom with two fingers, and act on
/// the picture without leaving the viewer: save it to a file through the share
/// sheet, or repost the post while keeping the original object keys.
Future<void> showPostImageGallery({
  required BuildContext context,
  required List<String> urls,
  int initialIndex = 0,
  bool canSave = true,
  bool canRepost = false,
  Future<void> Function(String url, int index)? onSave,
  Future<void> Function()? onRepost,
}) {
  if (urls.isEmpty) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: Tr.of(context, ar: 'إغلاق', en: 'Close'),
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => _PostGallery(
      urls: urls,
      initialIndex: initialIndex.clamp(0, urls.length - 1),
      canSave: canSave,
      canRepost: canRepost,
      onSave: onSave,
      onRepost: onRepost,
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _PostGallery extends StatefulWidget {
  const _PostGallery({
    required this.urls,
    required this.initialIndex,
    required this.canSave,
    required this.canRepost,
    this.onSave,
    this.onRepost,
  });

  final List<String> urls;
  final int initialIndex;
  final bool canSave;
  final bool canRepost;
  final Future<void> Function(String url, int index)? onSave;
  final Future<void> Function()? onRepost;

  @override
  State<_PostGallery> createState() => _PostGalleryState();
}

class _PostGalleryState extends State<_PostGallery> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            PageView.builder(
              controller: _pages,
              itemCount: widget.urls.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: WingsImage(
                    url: widget.urls[index],
                    fit: BoxFit.contain,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              top: Space.xs,
              start: Space.xs,
              child: _GalleryButton(
                icon: Icons.close_rounded,
                tooltip: Tr.of(context, ar: 'إغلاق', en: 'Close'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            if (widget.urls.length > 1)
              PositionedDirectional(
                top: Space.md,
                end: Space.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.urls.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            PositionedDirectional(
              start: Space.md,
              end: Space.md,
              bottom: Space.md,
              child: Row(
                children: <Widget>[
                  if (widget.canSave && widget.onSave != null)
                    Expanded(
                      child: _BottomAction(
                        icon: Icons.download_rounded,
                        label: Tr.of(context, ar: 'حفظ', en: 'Save'),
                        busy: _busy,
                        onTap: () async {
                          if (_busy) return;
                          setState(() => _busy = true);
                          try {
                            await widget.onSave!(widget.urls[_index], _index);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                      ),
                    ),
                  if (widget.canSave && widget.onSave != null)
                    const SizedBox(width: Space.sm),
                  if (widget.canRepost && widget.onRepost != null)
                    Expanded(
                      child: _BottomAction(
                        icon: Icons.repeat_rounded,
                        label: Tr.of(context, ar: 'إعادة نشر', en: 'Repost'),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await widget.onRepost!();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryButton extends StatelessWidget {
  const _GalleryButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.42),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: busy ? null : onTap,
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
      ),
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
