import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/community.dart';
import '../../data/models/user_profile.dart';
import '../profile/avatar_view.dart';
import '../social/user_handle.dart';
import 'community_providers.dart';

enum PeopleListKind { followers, following }

/// Followers / following of one account. Both lists read the same relationship
/// documents the follow button writes, so the numbers and the people always
/// agree.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key, required this.uid, required this.kind});

  final String uid;
  final PeopleListKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final title = kind == PeopleListKind.followers
        ? Tr.of(context, ar: 'المتابعون', en: 'Followers')
        : Tr.of(context, ar: 'يتابع', en: 'Following');
    final members = kind == PeopleListKind.followers
        ? ref.watch(followersProvider(uid))
        : ref.watch(followingListProvider(uid));

    return Scaffold(
      backgroundColor: palette.background,
      appBar: WingsAppBar(showBack: true, title: Text(title)),
      body: members.when(
        loading: () => const WingsLoading(),
        error: (error, stack) => WingsEmptyState(
          icon: Icons.cloud_off_rounded,
          title: AppLocalizations.of(context).commonErrorTitle,
          message: loadFailedText(context),
          actionLabel: AppLocalizations.of(context).commonRetry,
          onAction: () {
            if (kind == PeopleListKind.followers) {
              ref.invalidate(followersProvider(uid));
            } else {
              ref.invalidate(followingListProvider(uid));
            }
          },
        ),
        data: (items) {
          if (items.isEmpty) {
            return WingsEmptyState(
              icon: Icons.people_outline_rounded,
              title: kind == PeopleListKind.followers
                  ? Tr.of(context, ar: 'لا متابعين بعد', en: 'No followers yet')
                  : Tr.of(
                      context,
                      ar: 'لا يتابع أحدًا',
                      en: 'Not following anyone',
                    ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
            itemCount: items.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: Space.lg + 44 + Space.md,
              endIndent: Space.lg,
              color: palette.border,
            ),
            itemBuilder: (context, index) => _MemberRow(member: items[index]),
          );
        },
      ),
    );
  }
}

class _MemberRow extends ConsumerStatefulWidget {
  const _MemberRow({required this.member});

  final CommunityMember member;

  @override
  ConsumerState<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends ConsumerState<_MemberRow> {
  bool? _following;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final member = widget.member;
    final uid = ref.watch(authProvider)?.id;
    final followingIds = uid == null
        ? const <String>{}
        : ref.watch(followingIdsProvider(uid)).value ?? const <String>{};
    final following = _following ?? followingIds.contains(member.uid);
    final isMe = uid == member.uid;

    return InkWell(
      onTap: () => context.push(RoutePaths.publicProfile(member.uid)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            UserAvatar(
              uid: member.uid,
              photoVersion: member.profile?.photoVersion ?? 0,
              name: member.displayName,
              size: 44,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  UserHandle(
                    uid: member.uid,
                    username: member.username,
                    badges: member.profile?.badges ?? ProfileBadges.none,
                    style: context.text.labelSmall,
                  ),
                ],
              ),
            ),
            if (!isMe && uid != null)
              SizedBox(
                height: 32,
                child: TextButton(
                  onPressed: _busy ? null : () => _toggle(following),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    following
                        ? Tr.of(context, ar: 'إلغاء المتابعة', en: 'Unfollow')
                        : Tr.of(context, ar: 'متابعة', en: 'Follow'),
                    style: context.text.labelSmall?.copyWith(
                      color: following
                          ? palette.textSecondary
                          : palette.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(bool following) async {
    final profile = ref.read(profileProvider);
    if (profile == null || _busy) return;
    _busy = true;
    setState(() => _following = !following);
    try {
      await ref
          .read(communityRepositoryProvider)
          .setFollowing(
            actor: profile,
            target: widget.member.uid,
            follow: !following,
          );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _following = following);
      context.showSnack(userFacingError(context, error), isError: true);
    } finally {
      _busy = false;
    }
  }
}
