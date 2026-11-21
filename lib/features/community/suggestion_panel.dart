import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_image.dart';
import '../../data/models/anime.dart';
import '../../data/models/user_profile.dart';
import '../profile/avatar_view.dart';
import '../social/username_text.dart';
import 'community_providers.dart';

enum SuggestionKind { mention, anime }

/// What the caret is currently inside: `@que` or `#title`.
class ActiveTrigger {
  const ActiveTrigger({
    required this.kind,
    required this.query,
    required this.start,
    required this.end,
  });

  final SuggestionKind kind;
  final String query;

  /// Range to replace when a suggestion is accepted, trigger included.
  final int start;
  final int end;
}

/// Detects an unfinished `@handle` or `#anime` right before the caret.
///
/// Only the text before the caret is inspected, and a trigger that began before
/// a newline is ignored, so editing an older part of a long post never opens a
/// stale picker.
ActiveTrigger? detectTrigger(TextEditingController controller) {
  final selection = controller.selection;
  if (!selection.isValid || selection.start < 0) return null;
  final text = controller.text;
  final before = text.substring(0, selection.start.clamp(0, text.length));

  final mention = RegExp(r'(^|[\s\n])@([A-Za-z0-9_]{0,20})$')
      .firstMatch(before);
  if (mention != null) {
    return ActiveTrigger(
      kind: SuggestionKind.mention,
      query: mention.group(2)!,
      start: selection.start - mention.group(0)!.length + 1,
      end: selection.start,
    );
  }
  final anime = RegExp(r'(^|[\s\n])#([^#\n]{1,40})$').firstMatch(before);
  if (anime != null) {
    return ActiveTrigger(
      kind: SuggestionKind.anime,
      query: anime.group(2)!.trim(),
      start: selection.start - anime.group(0)!.length + 1,
      end: selection.start,
    );
  }
  return null;
}

/// Replaces the trigger with the chosen reference and keeps the caret after it.
void applySuggestion(
  TextEditingController controller,
  ActiveTrigger trigger,
  String replacement,
) {
  final text = controller.text;
  final before = text.substring(0, trigger.start);
  final after = text.substring(trigger.end.clamp(0, text.length));
  // One space after the reference, never two when the text already had one.
  final inserted = (after.isEmpty || !after.startsWith(' '))
      ? '$replacement '
      : replacement;
  controller.value = TextEditingValue(
    text: '$before$inserted$after',
    selection: TextSelection.collapsed(offset: before.length + inserted.length),
  );
}

/// Users matching the typed handle, ordered by how close the handle is and
/// then by the follow relationship.
final mentionSuggestionsProvider = FutureProvider.autoDispose
    .family<List<UserProfile>, String>((ref, query) async {
      final uid = ref.watch(authProvider)?.id;
      final following = uid == null
          ? const <String>{}
          : ref.watch(followingIdsProvider(uid)).value ?? const <String>{};
      final results = await ref
          .watch(communityRepositoryProvider)
          .suggestUsers(query.trim().toLowerCase());
      final normalized = query.trim().toLowerCase();
      final sorted = <UserProfile>[...results];
      int rank(UserProfile profile) {
        final handle = profile.normalizedUsername;
        if (handle == normalized) return 0;
        if (handle.startsWith(normalized)) return 1;
        return 2;
      }

      sorted.sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        final aFollows = following.contains(a.uid) ? 0 : 1;
        final bFollows = following.contains(b.uid) ? 0 : 1;
        if (aFollows != bFollows) return aFollows.compareTo(bFollows);
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      });
      return sorted.take(8).toList(growable: false);
    });

/// Anime suggestions from the real Wings catalogue, using the same search the
/// rest of the app uses so no invented titles can appear.
final animeSuggestionsProvider = FutureProvider.autoDispose
    .family<List<Anime>, String>((ref, query) async {
      final text = query.trim();
      try {
        final repository = ref.watch(animeRepositoryProvider);
        // A bare `#` still opens the picker with the newest titles instead of
        // an empty card, so the gesture is discoverable.
        final paged = text.isEmpty
            ? await repository.browse(const BrowseQuery())
            : await repository.search(text);
        return paged.items.take(6).toList(growable: false);
      } on Object {
        return const <Anime>[];
      }
    });

/// The suggestion list shown under a composer.
class SuggestionPanel extends ConsumerWidget {
  const SuggestionPanel({
    super.key,
    required this.trigger,
    required this.onPickUser,
    required this.onPickAnime,
  });

  final ActiveTrigger trigger;
  final ValueChanged<UserProfile> onPickUser;
  final ValueChanged<Anime> onPickAnime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: Space.xs),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: palette.border),
      ),
      child: trigger.kind == SuggestionKind.mention
          ? _mentions(context, ref, palette)
          : _anime(context, ref, palette),
    );
  }

  Widget _mentions(BuildContext context, WidgetRef ref, palette) {
    final results = ref.watch(mentionSuggestionsProvider(trigger.query));
    final uid = ref.watch(authProvider)?.id;
    final following = uid == null
        ? const <String>{}
        : ref.watch(followingIdsProvider(uid)).value ?? const <String>{};
    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.md),
        child: WingsLoading(size: 16),
      ),
      error: (error, stack) => _empty(context, palette),
      data: (users) {
        if (users.isEmpty) return _empty(context, palette);
        return ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: Space.xxs),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final isFollowing = following.contains(user.uid);
            final isMe = user.uid == uid;
            return InkWell(
              onTap: () => onPickUser(user),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + 2,
                  vertical: Space.xs + 2,
                ),
                child: Row(
                  children: <Widget>[
                    UserAvatar(
                      uid: user.uid,
                      photoVersion: user.photoVersion,
                      name: user.displayName,
                      size: 34,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          UsernameText(
                            username: user.username,
                            badges: user.badges,
                            style: context.text.labelMedium,
                          ),
                          Text(
                            user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      isMe
                          ? Tr.of(context, ar: 'أنت', en: 'You')
                          : isFollowing
                          ? Tr.of(context, ar: 'تتابعه', en: 'Following')
                          : '',
                      style: context.text.labelSmall?.copyWith(
                        color: palette.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _anime(BuildContext context, WidgetRef ref, palette) {
    final results = ref.watch(animeSuggestionsProvider(trigger.query));
    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.md),
        child: WingsLoading(size: 16),
      ),
      error: (error, stack) => _empty(context, palette),
      data: (items) {
        if (items.isEmpty) return _empty(context, palette);
        return ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: Space.xxs),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final anime = items[index];
            return InkWell(
              onTap: () => onPickAnime(anime),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + 2,
                  vertical: Space.xs + 2,
                ),
                child: Row(
                  children: <Widget>[
                    WingsImage(
                      url: anime.imageUrl,
                      width: 32,
                      height: 45,
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            anime.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium,
                          ),
                          if ((anime.englishTitle ?? '').isNotEmpty &&
                              anime.englishTitle != anime.title)
                            Text(
                              anime.englishTitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 14,
                      color: palette.textMuted,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _empty(BuildContext context, palette) => Padding(
    padding: const EdgeInsets.all(Space.md),
    child: Row(
      children: <Widget>[
        Icon(Icons.search_off_rounded, size: 16, color: palette.textMuted),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            trigger.kind == SuggestionKind.mention
                ? Tr.of(
                    context,
                    ar: 'لا حسابات مطابقة',
                    en: 'No matching accounts',
                  )
                : Tr.of(
                    context,
                    ar: 'لا أنميات مطابقة',
                    en: 'No matching anime',
                  ),
            style: context.text.labelSmall?.copyWith(color: palette.textMuted),
          ),
        ),
        TextButton(
          onPressed: () => context.push(RoutePaths.search),
          child: Text(Tr.of(context, ar: 'البحث', en: 'Search')),
        ),
      ],
    ),
  );
}
