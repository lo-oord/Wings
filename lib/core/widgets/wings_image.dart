import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import 'wings_feedback.dart';

/// Network artwork with caching, a stable placeholder and a branded fallback.
class WingsImage extends StatelessWidget {
  const WingsImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.alignment = Alignment.center,
  });

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final source = url;
    if (source == null || source.isEmpty) {
      return ClipRRect(borderRadius: radius, child: _fallback(context));
    }

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = width != null && width!.isFinite && width! > 0
        ? (width! * pixelRatio).round()
        : null;

    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: source,
        fit: fit,
        width: width,
        height: height,
        alignment: alignment,
        memCacheWidth: cacheWidth,
        fadeInDuration: const Duration(milliseconds: 240),
        placeholder: (context, _) => WingsSkeleton(
          width: width,
          height: height,
          borderRadius: BorderRadius.zero,
        ),
        errorWidget: (context, _, _) => _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: width,
      height: height,
      color: palette.surfaceAlt,
      alignment: Alignment.center,
      child: WingsMark(size: 26, opacity: 0.35),
    );
  }
}

/// The Wings wing mark, used for branding moments and empty states.
class WingsMark extends StatelessWidget {
  const WingsMark({super.key, this.size = 32, this.opacity = 1});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Image.asset(
        'assets/branding/icon_foreground.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, _, _) => Icon(
          Icons.flutter_dash_rounded,
          size: size * 0.8,
          color: context.palette.primary,
        ),
      ),
    );
  }
}

/// App branding lockup: wing mark plus wordmark.
class WingsLockup extends StatelessWidget {
  const WingsLockup({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WingsMark(size: size),
        const SizedBox(width: Space.sm),
        Text(
          'Wings',
          style: context.text.titleLarge?.copyWith(
            fontSize: size * 0.64,
            fontWeight: FontWeight.w700,
            height: 1.05,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}
