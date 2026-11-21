import 'dart:math' as math;

import '../../data/models/community.dart';

/// Everything the feed ranking needs, gathered from systems Wings already has:
/// the follow graph, the viewer's library (anime interests), personal hides and
/// blocks, and the local view history.
class FeedSignals {
  const FeedSignals({
    this.following = const <String>{},
    this.animeWeights = const <String, double>{},
    this.hidden = const <String>{},
    this.blocked = const <String>{},
    this.viewedPosts = const <String>{},
    this.likedAuthors = const <String>{},
    this.authorsWithReplies = const <String>{},
    this.hashtagWeights = const <String, double>{},
    this.soundWeights = const <String, double>{},
    this.now,
  });

  final Set<String> following;

  /// Anime id → weight, built from favourites, history and saved episodes.
  final Map<String, double> animeWeights;

  final Set<String> hidden;
  final Set<String> blocked;

  /// Ids of Reels already watched; they are demoted, never hidden.
  final Set<String> viewedPosts;

  /// Authors the viewer liked at least once.
  final Set<String> likedAuthors;

  /// Authors the viewer commented on or replied to.
  final Set<String> authorsWithReplies;

  /// Hashtag slug → weight, learned from the viewer's own likes, saves,
  /// comments and watch time. This is what makes two accounts see two
  /// different orders of the same page.
  final Map<String, double> hashtagWeights;

  /// Sound key → weight, learned the same way (using a sound counts too).
  final Map<String, double> soundWeights;

  /// Injectable clock so the ranking is testable.
  final DateTime? now;

  bool get isNewViewer =>
      following.isEmpty &&
      animeWeights.isEmpty &&
      likedAuthors.isEmpty &&
      authorsWithReplies.isEmpty;

  FeedSignals withNow(DateTime value) => FeedSignals(
    following: following,
    animeWeights: animeWeights,
    hidden: hidden,
    blocked: blocked,
    viewedPosts: viewedPosts,
    likedAuthors: likedAuthors,
    authorsWithReplies: authorsWithReplies,
    hashtagWeights: hashtagWeights,
    soundWeights: soundWeights,
    now: value,
  );
}

/// A scored post plus the reasons it scored, which keeps the ordering
/// explainable and testable instead of an opaque number.
class RankedPost {
  const RankedPost({
    required this.post,
    required this.score,
    required this.relationship,
    required this.interest,
    required this.engagement,
    required this.recency,
  });

  final Post post;
  final double score;
  final double relationship;
  final double interest;
  final double engagement;
  final double recency;
}

/// Personalised ordering for the community feed and for Reels.
///
/// The algorithm is deliberately simple and explainable:
///
/// score = recency + relationship + anime interest + engagement + diversity
///
/// * recency decays with a 3-day half-life, so nothing old can win forever;
/// * relationship rewards accounts the viewer follows, likes or talks to;
/// * interest rewards posts about the anime the viewer actually watches;
/// * engagement is logarithmic, so 10 000 likes are not 1 000× a post with 10;
/// * popularity alone can never beat a much fresher and more relevant post;
/// * new members get a balanced default (recency + mild engagement), never an
///   empty feed.
///
/// It runs on a bounded page of candidates, not on the whole collection: the
/// same amount of Firestore reads as a plain chronological page.
class CommunityRanking {
  const CommunityRanking._();

  static const Duration halfLife = Duration(days: 3);

  static double _recency(DateTime createdAt, DateTime now) {
    final age = now.difference(createdAt);
    final hours = age.inMinutes / 60.0;
    if (hours <= 0) return 1;
    final halvings = hours / (halfLife.inHours);
    return math.pow(0.5, halvings).toDouble();
  }

  static double _interest(Post post, FeedSignals signals) {
    if (post.animeRefs.isEmpty) return 0;
    var best = 0.0;
    for (final ref in post.animeRefs) {
      final weight = signals.animeWeights[ref.id] ?? 0;
      if (weight > best) best = weight;
    }
    return best.clamp(0, 1).toDouble();
  }

  static double _hashtagInterest(Post post, FeedSignals signals) {
    if (signals.hashtagWeights.isEmpty) return 0;
    var best = 0.0;
    for (final tag in post.hashtags) {
      final weight = signals.hashtagWeights[tag] ?? 0;
      if (weight > best) best = weight;
    }
    if (post.soundKey.isNotEmpty) {
      final sound = signals.soundWeights[post.soundKey] ?? 0;
      if (sound > best) best = sound;
    }
    return best.clamp(0, 1).toDouble();
  }

  static double _relationship(Post post, FeedSignals signals) {
    var score = 0.0;
    if (signals.following.contains(post.authorUid)) score += 0.9;
    if (signals.likedAuthors.contains(post.authorUid)) score += 0.35;
    if (signals.authorsWithReplies.contains(post.authorUid)) score += 0.25;
    return score.clamp(0, 1.2).toDouble();
  }

  static double _engagement(Post post) {
    final likes = math.log(1 + post.likeCount) / math.ln10;
    final comments = math.log(1 + post.commentCount) / math.ln10;
    // Capped so a viral post cannot dominate the whole page.
    return ((likes * 0.35) + (comments * 0.5)).clamp(0, 0.9).toDouble();
  }

  /// Ranks [candidates] for one viewer.
  ///
  /// Hidden and blocked authors are removed, duplicates are dropped, and the
  /// result never shows the same author twice in a row while other authors are
  /// still available.
  static List<Post> rank(
    Iterable<Post> candidates,
    FeedSignals signals, {
    int? limit,
  }) {
    final now = signals.now ?? DateTime.now();
    final seen = <String>{};
    final scored = <RankedPost>[];
    for (final post in candidates) {
      if (post.id.isEmpty || !seen.add(post.id)) continue;
      if (signals.hidden.contains(post.id)) continue;
      if (signals.blocked.contains(post.authorUid)) continue;
      final recency = _recency(post.createdAt, now);
      final relationship = _relationship(post, signals);
      final interest = _interest(post, signals);
      final tagInterest = _hashtagInterest(post, signals);
      final engagement = _engagement(post);
      final viewedPenalty = signals.viewedPosts.contains(post.id) ? 0.35 : 0.0;
      final score =
          (recency * 1.0) +
          relationship +
          (interest * 1.1) +
          (tagInterest * 0.8) +
          engagement -
          viewedPenalty;
      scored.add(
        RankedPost(
          post: post,
          score: score,
          relationship: relationship,
          interest: interest,
          engagement: engagement,
          recency: recency,
        ),
      );
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // A stable, deterministic tie-break keeps two builds identical.
      return b.post.createdAt.compareTo(a.post.createdAt);
    });

    final ordered = _pinnedFirst(
      _spreadAuthors(scored.map((item) => item.post).toList()),
    );
    if (limit == null || ordered.length <= limit) return ordered;
    return ordered.sublist(0, limit);
  }

  /// A pinned post (Owner choice) always sits at the top of the page, in the
  /// order it was pinned, without disturbing the rest of the ranking.
  static List<Post> _pinnedFirst(List<Post> posts) {
    final pinned = <Post>[
      for (final post in posts)
        if (post.pinned) post,
    ];
    if (pinned.isEmpty) return posts;
    return <Post>[
      ...pinned,
      for (final post in posts)
        if (!post.pinned) post,
    ];
  }

  /// Prevents a run of posts from the same account when alternatives exist.
  static List<Post> _spreadAuthors(List<Post> posts) {
    final remaining = <Post>[...posts];
    final result = <Post>[];
    String? lastAuthor;
    while (remaining.isNotEmpty) {
      var index = 0;
      if (remaining.first.authorUid == lastAuthor) {
        final alternative = remaining.indexWhere(
          (post) => post.authorUid != lastAuthor,
        );
        if (alternative > 0) index = alternative;
      }
      final next = remaining.removeAt(index);
      result.add(next);
      lastAuthor = next.authorUid;
    }
    return result;
  }
}
