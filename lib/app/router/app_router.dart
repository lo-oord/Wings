import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/anime.dart';
import '../../features/auth/auth_screens.dart';
import '../../features/details/anime_details_screen.dart';
import '../../features/downloads/downloads_screen.dart';
import '../../features/explore/catalog_screen.dart';
import '../../features/explore/explore_screen.dart';
import '../../features/explore/genre_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/player/player_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/public_profile_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/about_screen.dart';
import '../../features/settings/legal_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/social/episode_comments_screen.dart';
import '../../features/shell/app_shell.dart';
import '../providers.dart';
import '../theme/app_tokens.dart';
import '../theme/context_ext.dart';
import 'route_paths.dart';

/// Routes that belong to the sign-in journey. They stay reachable while no
/// account is signed in, so the redirect below never traps the user.
const Set<String> _authRoutes = <String>{
  RoutePaths.welcome,
  RoutePaths.login,
  RoutePaths.register,
  RoutePaths.forgot,
  RoutePaths.verify,
};

/// One shared page transition: a short fade with a small upward slide, so
/// opening a screen never feels like a hard cut and going back always mirrors
/// it. Reduced-motion users get no animation at all.
CustomTransitionPage<void> _wingsPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  final duration = reduceMotion ? Duration.zero : Motion.page;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Motion.enter),
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Motion.emphasized),
              ),
          child: child,
        ),
      );
    },
  );
}

/// Bridges Riverpod state to GoRouter so a sign-in, sign-out, or finishing the
/// onboarding immediately re-evaluates the redirect instead of leaving the app
/// on a screen that no longer applies.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
    ref.listen(settingsProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final settings = ref.read(settingsProvider);
  final signedIn = ref.read(authProvider) != null;
  final initialLocation = !settings.onboardingDone
      ? RoutePaths.onboarding
      : (!signedIn && !settings.guestMode
            ? RoutePaths.welcome
            : RoutePaths.latest);
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  String? redirect(BuildContext context, GoRouterState state) {
    final current = ref.read(settingsProvider);
    final account = ref.read(authProvider);
    final location = state.matchedLocation;
    if (!current.onboardingDone) {
      return location == RoutePaths.onboarding ? null : RoutePaths.onboarding;
    }
    if (account == null && !current.guestMode) {
      return _authRoutes.contains(location) ? null : RoutePaths.welcome;
    }
    if (account != null && location == RoutePaths.welcome) {
      return RoutePaths.latest;
    }
    return null;
  }

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refresh,
    redirect: redirect,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.onboarding,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const OnboardingScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.latest,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.explore,
                builder: (context, state) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.library,
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.search,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const SearchScreen()),
      ),
      GoRoute(
        path: '/anime/:id',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          AnimeDetailsScreen(
            animeId: Uri.decodeComponent(state.pathParameters['id'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/catalog/:kind',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          CatalogScreen(kind: state.pathParameters['kind'] ?? 'newest'),
        ),
      ),
      GoRoute(
        path: '/genre/:name',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          GenreScreen(
            genre: Uri.decodeComponent(state.pathParameters['name'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/watch/:animeId/:episodeId',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          PlayerScreen(
            animeId: Uri.decodeComponent(state.pathParameters['animeId'] ?? ''),
            episodeId: Uri.decodeComponent(
              state.pathParameters['episodeId'] ?? '',
            ),
            initialAnime: state.extra is Anime ? state.extra! as Anime : null,
          ),
        ),
      ),
      GoRoute(
        path: '/episode/:episodeId/comments',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          EpisodeCommentsScreen(
            episodeId: Uri.decodeComponent(
              state.pathParameters['episodeId'] ?? '',
            ),
            episodeTitle: state.extra is String ? state.extra! as String : '',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.downloads,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const DownloadsScreen()),
      ),
      GoRoute(
        path: RoutePaths.profile,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const ProfileScreen()),
      ),
      GoRoute(
        path: '/user/:uid',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          PublicProfileScreen(
            uid: Uri.decodeComponent(state.pathParameters['uid'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const NotificationsScreen()),
      ),
      GoRoute(
        path: RoutePaths.welcome,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const WelcomeScreen()),
      ),
      GoRoute(
        path: RoutePaths.login,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const LoginScreen()),
      ),
      GoRoute(
        path: RoutePaths.register,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const RegisterScreen()),
      ),
      GoRoute(
        path: RoutePaths.forgot,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: RoutePaths.verify,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const VerifyEmailScreen()),
      ),
      GoRoute(
        path: RoutePaths.about,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AboutScreen()),
      ),
      GoRoute(
        path: '/legal/:kind',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          LegalScreen(kind: state.pathParameters['kind'] ?? 'privacy'),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.explore_off_rounded,
                size: 40,
                color: context.palette.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.stateErrorNotFound,
                style: context.text.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(RoutePaths.latest),
                child: Text(context.l10n.navLatest),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});
