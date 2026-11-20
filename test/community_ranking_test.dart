import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/community.dart';
import 'package:wings/features/community/community_ranking.dart';

Post post({
  required String id,
  required String author,
  required int hoursAgo,
  int likes = 0,
  int comments = 0,
  List<String> animeIds = const <String>[],
}) => Post(
  id: id,
  authorUid: author,
  authorUsername: author,
  authorName: author,
  text: 'text $id',
  imageKeys: const <String>[],
  createdAt: DateTime(2026, 1, 1).subtract(Duration(hours: hoursAgo)),
  updatedAt: DateTime(2026, 1, 1).subtract(Duration(hours: hoursAgo)),
  likeCount: likes,
  commentCount: comments,
  animeRefs: <AnimeRef>[
    for (final id in animeIds) AnimeRef(id: id, title: 'anime $id'),
  ],
);

void main() {
  final now = DateTime(2026, 1, 1);

  test('a brand new member still gets content, never an empty feed', () {
    final ranked = CommunityRanking.rank(<Post>[
      post(id: 'a', author: 'u1', hoursAgo: 30),
      post(id: 'b', author: 'u2', hoursAgo: 1),
    ], FeedSignals(now: now));
    expect(ranked, isNotEmpty);
    expect(ranked.length, 2);
  });

  test('fresher posts beat older ones when everything else is equal', () {
    final ranked = CommunityRanking.rank(<Post>[
      post(id: 'old', author: 'u1', hoursAgo: 72),
      post(id: 'new', author: 'u2', hoursAgo: 1),
    ], FeedSignals(now: now));
    expect(ranked.first.id, 'new');
  });

  test('anime interest reorders the same candidates per member', () {
    final candidates = <Post>[
      post(id: 'naruto', author: 'u1', hoursAgo: 6, animeIds: ['1']),
      post(id: 'onepiece', author: 'u2', hoursAgo: 6, animeIds: ['2']),
    ];
    final narutoFan = CommunityRanking.rank(
      candidates,
      FeedSignals(now: now, animeWeights: const <String, double>{'1': 1}),
    );
    final onePieceFan = CommunityRanking.rank(
      candidates,
      FeedSignals(now: now, animeWeights: const <String, double>{'2': 1}),
    );
    expect(narutoFan.first.id, 'naruto');
    expect(onePieceFan.first.id, 'onepiece');
  });

  test('popularity alone never outweighs a much fresher post', () {
    final ranked = CommunityRanking.rank(<Post>[
      post(
        id: 'viral',
        author: 'u1',
        hoursAgo: 500,
        likes: 50000,
        comments: 9000,
      ),
      post(id: 'fresh', author: 'u2', hoursAgo: 2, likes: 1),
    ], FeedSignals(now: now));
    expect(ranked.first.id, 'fresh');
  });

  test('duplicates, hidden posts and blocked authors are excluded', () {
    final ranked = CommunityRanking.rank(
      <Post>[
        post(id: 'keep', author: 'u1', hoursAgo: 1),
        post(id: 'keep', author: 'u1', hoursAgo: 1),
        post(id: 'hidden', author: 'u2', hoursAgo: 1),
        post(id: 'blocked', author: 'u3', hoursAgo: 1),
      ],
      FeedSignals(
        now: now,
        hidden: const <String>{'hidden'},
        blocked: const <String>{'u3'},
      ),
    );
    expect(ranked.map((item) => item.id).toList(), <String>['keep']);
  });

  test('the same author is not shown twice in a row when others exist', () {
    final ranked = CommunityRanking.rank(<Post>[
      post(id: 'a1', author: 'a', hoursAgo: 1),
      post(id: 'a2', author: 'a', hoursAgo: 1),
      post(id: 'a3', author: 'a', hoursAgo: 1),
      post(id: 'b1', author: 'b', hoursAgo: 40),
    ], FeedSignals(now: now));
    final authors = ranked.map((item) => item.authorUid).toList();
    expect(authors[0], 'a');
    expect(authors[1], 'b');
  });

  test('following an author raises their post but never hides the rest', () {
    final ranked = CommunityRanking.rank(<Post>[
      post(id: 'followed', author: 'friend', hoursAgo: 30),
      post(id: 'other', author: 'stranger', hoursAgo: 20),
    ], FeedSignals(now: now, following: const <String>{'friend'}));
    expect(ranked.first.id, 'followed');
    expect(ranked.length, 2);
  });

  test('a watched reel is demoted but still reachable', () {
    final ranked = CommunityRanking.rank(<Post>[
      post(id: 'seen', author: 'u1', hoursAgo: 1),
      post(id: 'unseen', author: 'u2', hoursAgo: 1),
    ], FeedSignals(now: now, viewedPosts: const <String>{'seen'}));
    expect(ranked.first.id, 'unseen');
    expect(ranked.length, 2);
  });
}
