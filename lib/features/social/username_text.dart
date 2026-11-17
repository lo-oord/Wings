import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../data/models/user_profile.dart';

/// Username presentation used everywhere a handle appears.
///
/// * plain handles use the blue accent,
/// * verified handles turn gold with a verification seal,
/// * developer handles turn gold and show the real Wings app icon,
/// * both badges can be visible at once without overlapping.
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

  static const Color _gold = Color(0xFFE3B341);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gold = badges.any;
    final color = gold ? _gold : palette.primary;
    final label = username.trim().isEmpty ? '@' : '@$username';
    final base = (style ?? context.text.labelMedium)?.copyWith(
      color: color,
      fontWeight: gold ? FontWeight.w700 : FontWeight.w600,
      shadows: gold
          ? <Shadow>[
              Shadow(color: _gold.withValues(alpha: 0.35), blurRadius: 8),
            ]
          : null,
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            label,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: base,
          ),
        ),
        if (badges.verified) ...<Widget>[
          const SizedBox(width: 3),
          const Icon(Icons.verified_rounded, size: 14, color: _gold),
        ],
        if (badges.developer) ...<Widget>[
          const SizedBox(width: 3),
          Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gold.withValues(alpha: 0.16),
              border: Border.all(color: _gold.withValues(alpha: 0.45)),
            ),
            padding: const EdgeInsets.all(1.5),
            child: Image.asset(
              'assets/branding/wings_icon.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Icon(
                Icons.flutter_dash_rounded,
                size: 10,
                color: _gold,
              ),
            ),
          ),
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
