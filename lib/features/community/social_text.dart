import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_paths.dart';
import '../../app/theme/context_ext.dart';
import '../../data/models/community.dart';

/// Renders a post or comment body with working `@mentions` and anime hashtags.
///
/// Links are resolved from the stored references, never from the text alone:
/// a hand-typed `@someone` that the author never picked is shown as plain text,
/// and a hashtag only opens an anime when its title matches a reference the
/// post actually carries (which is what keeps navigation on the real id).
class SocialText extends StatefulWidget {
  const SocialText({
    super.key,
    required this.text,
    this.mentions = const <MentionRef>[],
    this.animeRefs = const <AnimeRef>[],
    this.hashtags = const <String>[],
    this.style,
    this.maxLines,
    this.showAnimeChips = true,
    this.linkColor,
  });

  final String text;
  final List<MentionRef> mentions;
  final List<AnimeRef> animeRefs;

  /// Free community hashtags (normalized, no `#`). Each one opens the tag's
  /// results page; anime titles are matched from [animeRefs] instead.
  final List<String> hashtags;

  final TextStyle? style;
  final int? maxLines;
  final bool showAnimeChips;

  /// Comments use the green mark; posts keep the app accent.
  final Color? linkColor;

  @override
  State<SocialText> createState() => _SocialTextState();
}

class _Token {
  const _Token({required this.start, required this.end, required this.route});

  final int start;
  final int end;
  final String route;
}

class _SocialTextState extends State<SocialText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];
  String? _signature;
  List<_Token> _tokens = const <_Token>[];
  Set<String> _matchedAnimeIds = const <String>{};

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _compute(String text) {
    final signature = <String>[
      text,
      ...widget.mentions.map((item) => '${item.uid}:${item.username}'),
      ...widget.animeRefs.map((item) => '${item.id}:${item.title}'),
      ...widget.hashtags,
    ].join('|');
    if (signature == _signature) return;
    _signature = signature;
    _disposeRecognizers();
    final tokens = <_Token>[];
    final taken = <String>{};
    final matched = <String>{};
    final lower = text.toLowerCase();

    // Anime titles can contain spaces, so the longest title is matched first
    // and its range is claimed before short titles can overlap it.
    final refs = <AnimeRef>[...widget.animeRefs]
      ..sort((a, b) => b.title.length.compareTo(a.title.length));
    for (final ref in refs) {
      final title = ref.title.trim();
      if (title.isEmpty) continue;
      final needle = '#${title.toLowerCase()}';
      var from = 0;
      while (true) {
        final index = lower.indexOf(needle, from);
        if (index < 0) break;
        from = index + needle.length;
        final end = index + needle.length;
        if (tokens.any((token) => index < token.end && end > token.start)) {
          continue;
        }
        tokens.add(
          _Token(start: index, end: end, route: RoutePaths.anime(ref.id)),
        );
        matched.add(ref.id);
      }
    }

    // Free hashtags are matched after the anime titles, so a title that also
    // exists as a free tag keeps opening the anime page, never a search page.
    for (final tag in widget.hashtags) {
      final clean = tag.trim().toLowerCase();
      if (clean.isEmpty) continue;
      final needle = '#$clean';
      var from = 0;
      while (true) {
        final index = lower.indexOf(needle, from);
        if (index < 0) break;
        from = index + needle.length;
        final end = index + needle.length;
        if (tokens.any((token) => index < token.end && end > token.start)) {
          continue;
        }
        tokens.add(
          _Token(
            start: index,
            end: end,
            route: RoutePaths.communityHashtag(clean),
          ),
        );
      }
    }

    for (final mention in widget.mentions) {
      final username = mention.username.trim();
      if (username.isEmpty) continue;
      final needle = '@${username.toLowerCase()}';
      var from = 0;
      while (true) {
        final index = lower.indexOf(needle, from);
        if (index < 0) break;
        from = index + needle.length;
        final end = index + needle.length;
        if (tokens.any((token) => index < token.end && end > token.start)) {
          continue;
        }
        tokens.add(
          _Token(
            start: index,
            end: end,
            route: RoutePaths.publicProfile(mention.uid),
          ),
        );
      }
    }

    tokens.sort((a, b) => a.start.compareTo(b.start));
    _tokens = tokens;
    _matchedAnimeIds = matched;
    taken.clear();
  }

  @override
  Widget build(BuildContext context) {
    _compute(widget.text);
    final palette = context.palette;
    final base =
        widget.style ??
        context.text.bodyMedium?.copyWith(
          height: 1.65,
          color: palette.textPrimary,
        );
    final linkStyle = base?.copyWith(
      color: widget.linkColor ?? palette.primary,
      fontWeight: FontWeight.w600,
    );

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final token in _tokens) {
      if (token.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, token.start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (context.mounted) context.push(token.route);
        };
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: widget.text.substring(token.start, token.end),
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = token.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    final unmatched = widget.showAnimeChips
        ? <AnimeRef>[
            for (final ref in widget.animeRefs)
              if (!_matchedAnimeIds.contains(ref.id)) ref,
          ]
        : const <AnimeRef>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.text.isNotEmpty)
          Text.rich(
            TextSpan(style: base, children: spans),
            maxLines: widget.maxLines,
            overflow: widget.maxLines == null
                ? TextOverflow.clip
                : TextOverflow.ellipsis,
          ),
        if (unmatched.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final ref in unmatched)
                _AnimeChip(
                  // The stored title may have been renamed in the catalogue;
                  // the id is what opens the right page.
                  title: ref.title,
                  onTap: () => context.push(RoutePaths.anime(ref.id)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AnimeChip extends StatelessWidget {
  const _AnimeChip({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border),
        ),
        child: Text(
          '#$title',
          style: context.text.labelSmall?.copyWith(color: palette.primary),
        ),
      ),
    );
  }
}
