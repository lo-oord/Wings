import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../data/models/user_profile.dart';

/// Username presentation used everywhere a handle appears.
///
/// * plain handles use the blue accent,
/// * a verified handle turns **gold** with a gold seal,
/// * a developer handle turns **red** with a blue Wings mark,
/// * an account that is both is drawn in a shiny **purple-gold** gradient and
///   carries the seal and the blue mark together.
///
/// The marks never depend on a stored snapshot alone: callers pass the live
/// badges (or use [UserHandle]) so a grant shows up immediately.
class UsernameText extends StatelessWidget {
  const UsernameText({
    super.key,
    required this.username,
    this.badges = ProfileBadges.none,
    this.style,
    this.onTap,
    this.maxLines = 1,
  });

  final String username;
  final ProfileBadges badges;
  final TextStyle? style;
  final VoidCallback? onTap;
  final int maxLines;

  static const Color _gold = BrandColors.gold;
  static const Color _red = BrandColors.developerRed;
  static const Color _royal = BrandColors.royalPurple;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final royal = badges.both;
    final color = royal
        ? _royal
        : badges.verified
        ? _gold
        : badges.developer
        ? _red
        : palette.primary;
    final label = username.trim().isEmpty ? '@' : '@$username';
    final base = (style ?? context.text.labelMedium)?.copyWith(
      // The gradient is painted over white text, so the base colour is only a
      // fallback for platforms that skip the shader.
      color: royal ? Colors.white : color,
      fontWeight: badges.any ? FontWeight.w700 : FontWeight.w600,
      shadows: royal
          ? <Shadow>[
              Shadow(color: _royal.withValues(alpha: 0.45), blurRadius: 10),
              Shadow(color: _gold.withValues(alpha: 0.35), blurRadius: 16),
            ]
          : badges.verified
          ? <Shadow>[
              Shadow(color: _gold.withValues(alpha: 0.35), blurRadius: 8),
            ]
          : badges.developer
          ? <Shadow>[Shadow(color: _red.withValues(alpha: 0.30), blurRadius: 8)]
          : null,
    );

    Widget text = Text(
      label,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
    if (royal) {
      text = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => BrandColors.royalGradient.createShader(
          Rect.fromLTWH(0, 0, bounds.width, bounds.height),
        ),
        child: text,
      );
    } else if (badges.verified) {
      text = _GoldShine(child: text);
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(child: text),
        if (badges.verified) ...<Widget>[
          const SizedBox(width: 3),
          const Icon(Icons.verified_rounded, size: 14, color: _gold),
        ],
        if (badges.developer) ...<Widget>[
          const SizedBox(width: 3),
          const _DeveloperMark(),
        ],
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: content,
      ),
    );
  }
}

/// The blue Wings mark of a developer account.
class _DeveloperMark extends StatelessWidget {
  const _DeveloperMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[BrandColors.developerBlue, Color(0xFF1B4FB8)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.75),
          width: 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.developerBlue.withValues(alpha: 0.45),
            blurRadius: 6,
          ),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: Image.asset(
        'assets/branding/wings_icon.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) =>
            const Icon(Icons.code_rounded, size: 10, color: Colors.white),
      ),
    );
  }
}

/// A slow moving gold highlight for verified handles. One controller per
/// visible handle, and it only exists while the gold mark is on screen.
class _GoldShine extends StatefulWidget {
  const _GoldShine({required this.child});

  final Widget child;

  @override
  State<_GoldShine> createState() => _GoldShineState();
}

class _GoldShineState extends State<_GoldShine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const <Color>[
            BrandColors.goldDeep,
            BrandColors.gold,
            Color(0xFFFFF6D6),
            BrandColors.gold,
            BrandColors.goldDeep,
          ],
          stops: const <double>[0, 0.32, 0.5, 0.68, 1],
          transform: GradientRotation(_controller.value * 6.283),
        ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
        child: child,
      ),
    );
  }
}

/// Avatar frame that mirrors the handle signature.
///
/// Verified accounts get a gold ring, developer accounts a blue ring, and an
/// account with both gets the royal purple-gold ring. Everyone sees the same
/// frame, because it is drawn from the public mirror.
class ProfileAvatarFrame extends StatefulWidget {
  const ProfileAvatarFrame({
    super.key,
    required this.badges,
    required this.child,
    this.padding = 2.5,
    this.sealSize = 18,
  });

  final ProfileBadges badges;
  final Widget child;
  final double padding;
  final double sealSize;

  @override
  State<ProfileAvatarFrame> createState() => _ProfileAvatarFrameState();
}

class _ProfileAvatarFrameState extends State<ProfileAvatarFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.badges.verified) _shine.repeat();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatarFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.badges.verified && !_shine.isAnimating) {
      _shine.repeat();
    } else if (!widget.badges.verified && _shine.isAnimating) {
      _shine.stop();
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badges = widget.badges;
    if (!badges.any) return widget.child;
    final gradient = badges.both
        ? BrandColors.royalGradient
        : badges.verified
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              BrandColors.goldDeep,
              BrandColors.gold,
              Color(0xFFFFF4CC),
              BrandColors.gold,
              BrandColors.goldDeep,
            ],
            stops: <double>[0, 0.3, 0.5, 0.7, 1],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[BrandColors.developerBlue, Color(0xFF1B4FB8)],
          );
    final glow = badges.both
        ? BrandColors.royalPurple
        : badges.verified
        ? BrandColors.gold
        : BrandColors.developerBlue;

    Widget ring;
    if (badges.verified) {
      ring = AnimatedBuilder(
        animation: _shine,
        child: widget.child,
        builder: (context, child) => Container(
          padding: EdgeInsets.all(widget.padding),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: badges.both
                  ? <Color>[
                      BrandColors.royalPurple,
                      BrandColors.gold,
                      Color(0xFFFFF7DD),
                      BrandColors.royalPurple,
                    ]
                  : const <Color>[
                      BrandColors.goldDeep,
                      BrandColors.gold,
                      Color(0xFFFFF7DD),
                      BrandColors.gold,
                      BrandColors.goldDeep,
                    ],
              stops: badges.both
                  ? const <double>[0, 0.35, 0.5, 1]
                  : const <double>[0, 0.3, 0.5, 0.7, 1],
              transform: GradientRotation(_shine.value * 6.283),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: BrandColors.gold.withValues(
                  alpha: 0.34 + (_shine.value * 0.22),
                ),
                blurRadius: 14 + (_shine.value * 8),
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        ),
      );
    } else {
      ring = Container(
        padding: EdgeInsets.all(widget.padding),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: glow.withValues(alpha: 0.38),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: widget.child,
      );
    }

    // Kept for the shared stack below.
    //

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        ring,
        if (badges.verified)
          PositionedDirectional(
            bottom: -1,
            end: -1,
            child: Container(
              width: widget.sealSize,
              height: widget.sealSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BrandColors.gold,
                border: Border.all(color: Colors.white, width: 1.4),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: BrandColors.gold.withValues(alpha: 0.45),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                Icons.verified_rounded,
                color: Colors.white,
                size: widget.sealSize * 0.66,
              ),
            ),
          ),
      ],
    );
  }
}
