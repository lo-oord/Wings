abstract final class RoutePaths {
  static const String onboarding = '/onboarding';
  static const String latest = '/latest';
  static const String community = '/community';
  static const String explore = '/explore';
  static const String library = '/library';
  static const String settings = '/settings';
  static const String search = '/search';

  static String catalog(String kind) => '/catalog/$kind';
  static const String downloads = '/downloads';
  static const String profile = '/profile';
  static const String notifications = '/notifications';
  static const String about = '/about';
  static const String welcome = '/auth';
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String forgot = '/auth/forgot';
  static const String verify = '/auth/verify';
  static const String complete = '/auth/complete';

  static String anime(String id) => '/anime/${Uri.encodeComponent(id)}';

  static String genre(String name) => '/genre/${Uri.encodeComponent(name)}';

  static String live(String channelId) =>
      '/live/${Uri.encodeComponent(channelId)}';

  /// Full-screen episode player opened from a community post. It is the same
  /// catalogue player, but reached without leaving the feed's own route stack.
  static String communityWatch({
    required String animeId,
    required String episodeId,
  }) =>
      '/community/watch/${Uri.encodeComponent(animeId)}/'
      '${Uri.encodeComponent(episodeId)}';

  static String watch({required String animeId, required String episodeId}) =>
      '/watch/${Uri.encodeComponent(animeId)}/${Uri.encodeComponent(episodeId)}';

  static String episodeComments(String episodeId) =>
      '/episode/${Uri.encodeComponent(episodeId)}/comments';

  static String legal(String kind) => '/legal/$kind';

  // Developer tools (Owner only). The screens verify the trusted role again and
  // the server refuses every administrative write from anyone else.
  static const String admin = '/admin';
  static const String adminUsers = '/admin/users';
  static const String adminPolicies = '/admin/policies';
  static const String adminReports = '/admin/reports';
  static const String adminMessages = '/admin/messages';
  static const String adminAnnouncements = '/admin/notifications';
  static const String adminMonitor = '/admin/monitor';
  static const String adminLog = '/admin/log';

  static String adminUser(String uid) =>
      '/admin/users/${Uri.encodeComponent(uid)}';

  static const String accountStatus = '/account-status';
  static const String ownerMessages = '/owner-messages';

  static String ownerMessage(String id) =>
      '/owner-message/${Uri.encodeComponent(id)}';

  static String publicProfile(String uid) =>
      '/user/${Uri.encodeComponent(uid)}';

  static String followers(String uid) =>
      '/user/${Uri.encodeComponent(uid)}/followers';

  static String following(String uid) =>
      '/user/${Uri.encodeComponent(uid)}/following';

  // Community. One feed inside the shell; the detail and composer are pushed
  // on top of it like any other screen in Wings.
  static const String communityCompose = '/community/new';
  static const String communitySaved = '/community/saved';
  static const String communityReels = '/community/reels';
  static const String communityReelCompose = '/community/reels/new';
  static const String communitySearch = '/community/search';

  /// Results of one community hashtag. The slug is normalized (no `#`, lower
  /// case) so one tag has exactly one destination.
  static String communityHashtag(String slug) =>
      '/community/tag/${Uri.encodeComponent(slug)}';

  static String communityPost(String postId) =>
      '/community/post/${Uri.encodeComponent(postId)}';

  // One-to-one messaging.
  static const String chats = '/chats';
  static const String chatNew = '/chats/new';
  static const String chatPrivacy = '/chats/privacy';

  static String chat(String chatId) => '/chats/${Uri.encodeComponent(chatId)}';
}
