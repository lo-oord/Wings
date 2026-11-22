import '../../app/router/route_paths.dart';

/// Turns an incoming link into an in-app route.
///
/// Two shapes are accepted so a link keeps working everywhere:
/// `https://wingsapp.vercel.app/open?type=anime&id=…` (also opens the website
/// when the app is absent) and the `wings://` scheme used by links the app
/// itself shares.
abstract final class DeepLinks {
  static const String scheme = 'wings';
  static const Set<String> hosts = <String>{'wingsapp.vercel.app'};

  static String? routeFor(Uri uri) {
    final isCustom = uri.scheme == scheme;
    final isSite =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        hosts.contains(uri.host);
    if (!isCustom && !isSite) return null;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final query = uri.queryParameters;
    String? type;
    String? id;
    String? episode = query['episode'];

    if (segments.isNotEmpty && segments.first == 'open') {
      type = query['type'];
      id = query['id'];
      episode = query['extra'] ?? episode;
    } else if (isCustom) {
      // wings://anime/<id> keeps "anime" in the host part.
      if (uri.host.isNotEmpty) {
        type = uri.host;
        id = segments.isEmpty ? null : segments.first;
        if (segments.length > 1 && type == 'watch') episode = segments[1];
      } else if (segments.isNotEmpty) {
        type = segments.first;
        id = segments.length > 1 ? segments[1] : null;
        if (segments.length > 2 && type == 'watch') episode = segments[2];
      }
    } else if (segments.length >= 2) {
      // https://wingsapp.vercel.app/anime/<id>, /community/post/<id>, /user/<uid>
      if (segments.first == 'community' && segments[1] == 'post') {
        type = 'post';
        id = segments.length > 2 ? segments[2] : null;
      } else if (segments.first == 'community' && segments[1] == 'tag') {
        type = 'tag';
        id = segments.length > 2 ? segments[2] : null;
      } else if (segments.first == 'watch' && segments.length > 2) {
        type = 'watch';
        id = segments[1];
        episode = segments[2];
      } else {
        type = segments.first;
        id = segments[1];
      }
    }

    if (type == null || id == null || id.isEmpty) return null;
    return switch (type) {
      'anime' => RoutePaths.anime(id),
      'post' || 'reel' => RoutePaths.communityPost(id),
      'user' || 'profile' => RoutePaths.publicProfile(id),
      'tag' => RoutePaths.communityHashtag(id),
      'watch' =>
        episode == null || episode.isEmpty
            ? RoutePaths.anime(id)
            : RoutePaths.watch(animeId: id, episodeId: episode),
      'live' => RoutePaths.live(id),
      _ => null,
    };
  }
}
