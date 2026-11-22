import 'package:flutter_test/flutter_test.dart';
import 'package:wings/core/services/deep_link_service.dart';

void main() {
  group('DeepLinks.routeFor', () {
    test('maps the website /open query to the in-app route', () {
      expect(
        DeepLinks.routeFor(
          Uri.parse(
            'https://wingsapp.vercel.app/open?type=anime&id=One%20Piece',
          ),
        ),
        '/anime/One%20Piece',
      );
      expect(
        DeepLinks.routeFor(
          Uri.parse('https://wingsapp.vercel.app/open?type=post&id=p1'),
        ),
        '/community/post/p1',
      );
    });

    test('accepts the custom scheme the app shares', () {
      expect(DeepLinks.routeFor(Uri.parse('wings://anime/a1')), '/anime/a1');
      expect(
        DeepLinks.routeFor(Uri.parse('wings://post/p9')),
        '/community/post/p9',
      );
      expect(DeepLinks.routeFor(Uri.parse('wings://user/u3')), '/user/u3');
    });

    test('understands readable website paths', () {
      expect(
        DeepLinks.routeFor(Uri.parse('https://wingsapp.vercel.app/anime/a2')),
        '/anime/a2',
      );
      expect(
        DeepLinks.routeFor(
          Uri.parse('https://wingsapp.vercel.app/community/post/p7'),
        ),
        '/community/post/p7',
      );
      expect(
        DeepLinks.routeFor(
          Uri.parse('https://wingsapp.vercel.app/community/tag/anime'),
        ),
        '/community/tag/anime',
      );
    });

    test('a watch link keeps its episode', () {
      expect(
        DeepLinks.routeFor(
          Uri.parse(
            'https://wingsapp.vercel.app/open?type=watch&id=a1&extra=e4',
          ),
        ),
        '/watch/a1/e4',
      );
    });

    test('ignores foreign hosts and unknown types', () {
      expect(
        DeepLinks.routeFor(Uri.parse('https://example.com/open?type=anime')),
        isNull,
      );
      expect(
        DeepLinks.routeFor(
          Uri.parse('https://wingsapp.vercel.app/open?type=settings&id=1'),
        ),
        isNull,
      );
    });
  });
}
