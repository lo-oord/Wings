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

/// Avatar frame that mirrors the handle signature.
///
/// Verified accounts get a gold ring, developer accounts a blue ring, and an
/// account with both gets the royal purple-gold ring. Everyone sees the same
/// frame, because it is drawn from the public mirror.
class ProfileAvatarFrame extends StatelessWidget {
  const ProfileAvatarFrame({
    super.key,
    required this.badges,
    required this.child,
    this.padding = 2.5,
  });

  final ProfileBadges badges;
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    if (!badges.any) return child;
    final gradient = badges.both
        ? BrandColors.royalGradient
        : badges.verified
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[BrandColors.gold, BrandColors.goldDeep],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[BrandColors.developerBlue, Color(0xFF1B4FB8)],
          );
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color:
                (badges.both
                        ? BrandColors.royalPurple
                        : badges.verified
                        ? BrandColors.gold
                        : BrandColors.developerBlue)
                    .withValues(alpha: 0.35),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}
