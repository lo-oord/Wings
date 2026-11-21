import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/errors/user_facing_error.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/hashtags.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import '../../data/models/community.dart';
import '../../data/models/user_profile.dart';
import '../profile/avatar_view.dart';
import 'post_card.dart';

/// Search across the community: posts, free hashtags, users and anime.
///
/// Search is deliberately separate from the personalised feed. A query must
/// return what it matched — a post is only shown when all of its words match —
/// while the order inside the result can still prefer the viewer's interests.
class CommunitySearchScreen extends ConsumerStatefulWidget {
  const CommunitySearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<CommunitySearchScreen> createState() =>
      _CommunitySearchScreenState();
}

class _CommunitySearchScreenState extends ConsumerState<CommunitySearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  Timer? _debounce;
  Future<_SearchBundle>? _results;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    if (_query.isNotEmpty) _run(_query);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      final query = value.trim();
      if (!mounted) return;
      setState(() => _query = query);
      if (query.isEmpty) {
        setState(() => _results = null);
        return;
      }
      _run(query);
    });
  }

  void _run(String query) {
    final repo = ref.read(communityRepositoryProvider);
    final animeRepo = ref.read(animeRepositoryProvider);
    final future = () async {
      final posts = await repo.searchPosts(query);
      final users = await repo.suggestUsers(query, limit: 6);
      final tags = await repo.suggestHashtags(query, limit: 8);
      List<Anime> anime = const <Anime>[];
      try {
        final paged = query.startsWith('#')
            ? await animeRepo.search(query.substring(1).trim())
            : await animeRepo.search(query);
        anime = paged.items.take(6).toList(growable: false);
      } on Object {
        anime = const <Anime>[];
      }
      return _SearchBundle(
        posts: posts,
        users: users,
        hashtags: tags,
        anime: anime,
      );
    }();
    setState(() => _results = future);
  }

  void _searchTag(String tag) {
    final slug = normalizeHashtag(tag);
    if (slug.isEmpty) return;
    _controller.text = '#$slug';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() => _query = '#$slug');
    _run('#$slug');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: WingsAppBar(
        showBack: true,
        title: Text(
          Tr.of(context, ar: 'بحث المجتمع', en: 'Community search'),
          style: context.text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.sm,
              Space.lg,
              Space.sm,
            ),
            child: TextField(
              controller: _controller,
              autofocus: widget.initialQuery.isEmpty,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              style: context.text.bodyMedium,
              decoration: InputDecoration(
                hintText: Tr.of(
                  context,
                  ar: 'ابحث عن منشور، هاشتاج، أنمي أو مستخدم',
                  en: 'Search posts, hashtags, anime or people',
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _query = '';
                            _results = null;
                          });
                        },
                      ),
                filled: true,
                fillColor: palette.surfaceAlt,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _body(palette)),
        ],
      ),
    );
  }

  Widget _body(dynamic palette) {
    if (_query.isEmpty) return _trending();
    final future = _results;
    if (future == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return FutureBuilder<_SearchBundle>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return WingsEmptyState(
            icon: Icons.cloud_off_rounded,
            title: Tr.of(context, ar: 'تعذّر البحث', en: 'Search failed'),
            message: loadFailedText(context),
            actionLabel: Tr.of(context, ar: 'إعادة', en: 'Retry'),
            onAction: () => _run(_query),
          );
        }
        final data = snapshot.data ?? const _SearchBundle();
        if (data.isEmpty) {
          return WingsEmptyState(
            icon: Icons.search_off_rounded,
            title: Tr.of(context, ar: 'لا نتائج', en: 'No results'),
            message: Tr.of(
              context,
              ar: 'جرّب كلمة أخرى أو هاشتاجًا مختلفًا.',
              en: 'Try another word or a different hashtag.',
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: Space.xxxl),
          children: <Widget>[
            if (data.hashtags.isNotEmpty) ...<Widget>[
              _SectionTitle(
                title: Tr.of(context, ar: 'الهاشتاجات', en: 'Hashtags'),
              ),
              for (final tag in data.hashtags)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.tag_rounded, size: 18),
                  title: Text(
                    '#${tag.name}',
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: tag.creatorUsername.isEmpty
                      ? Text(
                          Tr.of(
                            context,
                            ar: '${tag.usageCount} منشورًا',
                            en: '${tag.usageCount} posts',
                          ),
                          style: context.text.labelSmall,
                        )
                      : Text(
                          Tr.of(
                            context,
                            ar: 'أنشأه @${tag.creatorUsername} · ${tag.usageCount} منشورًا',
                            en: 'by @${tag.creatorUsername} · ${tag.usageCount} posts',
                          ),
                          style: context.text.labelSmall,
                        ),
                  onTap: () => _searchTag(tag.slug),
                  trailing: const Icon(Icons.chevron_left_rounded, size: 18),
                ),
            ],
            if (data.anime.isNotEmpty) ...<Widget>[
              _SectionTitle(
                title: Tr.of(context, ar: 'الأنمي', en: 'Anime'),
              ),
              for (final anime in data.anime)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.movie_outlined, size: 18),
                  title: Text(anime.title, style: context.text.bodyMedium),
                  onTap: () => context.push(RoutePaths.anime(anime.id)),
                  trailing: const Icon(Icons.chevron_left_rounded, size: 18),
                ),
            ],
            if (data.users.isNotEmpty) ...<Widget>[
              _SectionTitle(
                title: Tr.of(context, ar: 'المستخدمون', en: 'People'),
              ),
              for (final user in data.users)
                ListTile(
                  dense: true,
                  leading: UserAvatar(
                    uid: user.uid,
                    photoVersion: user.photoVersion,
                    name: user.displayName,
                    size: 32,
                  ),
                  title: Text(
                    user.displayName.isEmpty
                        ? '@${user.username}'
                        : user.displayName,
                    style: context.text.bodyMedium,
                  ),
                  subtitle: Text(
                    '@${user.username}',
                    style: context.text.labelSmall,
                  ),
                  onTap: () => context.push(RoutePaths.publicProfile(user.uid)),
                  trailing: const Icon(Icons.chevron_left_rounded, size: 18),
                ),
            ],
            if (data.posts.isNotEmpty) ...<Widget>[
              _SectionTitle(
                title: Tr.of(context, ar: 'المنشورات', en: 'Posts'),
              ),
              for (final post in data.posts)
                PostCard(
                  post: post,
                  onDeleted: () => setState(() => _run(_query)),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _trending() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      children: <Widget>[
        Text(
          Tr.of(
            context,
            ar: 'ابحث في المنشورات والهاشتاجات والأنميات والأعضاء.',
            en: 'Search posts, hashtags, anime and members.',
          ),
          style: context.text.bodySmall?.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: Space.md),
        FutureBuilder<List<HashtagInfo>>(
          future: ref.read(communityRepositoryProvider).suggestHashtags(''),
          builder: (context, snapshot) {
            final tags = snapshot.data ?? const <HashtagInfo>[];
            if (tags.isEmpty) return const SizedBox.shrink();
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: <Widget>[
                for (final tag in tags)
                  ActionChip(
                    avatar: const Icon(Icons.tag_rounded, size: 14),
                    label: Text('#${tag.name}'),
                    onPressed: () => _searchTag(tag.slug),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.xs,
      ),
      child: Text(
        title,
        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SearchBundle {
  const _SearchBundle({
    this.posts = const <Post>[],
    this.users = const <UserProfile>[],
    this.hashtags = const <HashtagInfo>[],
    this.anime = const <Anime>[],
  });

  final List<Post> posts;
  final List<UserProfile> users;
  final List<HashtagInfo> hashtags;
  final List<Anime> anime;

  bool get isEmpty =>
      posts.isEmpty && users.isEmpty && hashtags.isEmpty && anime.isEmpty;
}
