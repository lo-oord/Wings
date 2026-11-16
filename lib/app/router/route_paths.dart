abstract final class RoutePaths {
  static const String onboarding = '/onboarding';
  static const String latest = '/latest';
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

  static String anime(String id) => '/anime/${Uri.encodeComponent(id)}';

  static String genre(String name) => '/genre/${Uri.encodeComponent(name)}';

  static String watch({required String animeId, required String episodeId}) =>
      '/watch/${Uri.encodeComponent(animeId)}/${Uri.encodeComponent(episodeId)}';

  static String legal(String kind) => '/legal/$kind';
}
