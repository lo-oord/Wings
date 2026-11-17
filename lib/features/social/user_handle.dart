import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/user_profile.dart';
import 'username_text.dart';

/// A handle that follows its account.
///
/// Comments and replies store a display snapshot so they can be read without a
/// second lookup, but that snapshot goes stale when the author renames or an
/// administrator grants a badge. This widget keeps the stored value as the
/// instant fallback and switches to the live public mirror as soon as it
/// arrives, so a rename or a new gold/blue mark appears in every existing
/// comment without touching a single document.
class UserHandle extends ConsumerWidget {
  const UserHandle({
    super.key,
    required this.uid,
    required this.username,
    this.badges = ProfileBadges.none,
    this.style,
    this.onTap,
    this.maxLines = 1,
  });

  final String uid;
  final String username;
  final ProfileBadges badges;
  final TextStyle? style;
  final VoidCallback? onTap;
  final int maxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = uid.isEmpty
        ? null
        : ref.watch(publicProfileProvider(uid)).value;
    final name = (live?.username.trim().isNotEmpty ?? false)
        ? live!.username
        : username;
    final resolved = live == null ? badges : badges.merge(live.badges);
    return UsernameText(
      username: name,
      badges: resolved,
      style: style,
      onTap: onTap,
      maxLines: maxLines,
    );
  }
}
