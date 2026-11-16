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
import '../../features/search/search_screen.dart';
import '../../features/settings/about_screen.dart';
import '../../features/settings/legal_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../providers.dart';
import '../theme/context_ext.dart';
import 'route_paths.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final settings = ref.read(settingsProvider);
  final signedIn = ref.read(authProvider) != null;
  final initialLocation = !settings.onboardingDone
      ? RoutePaths.onboarding
      : (!signedIn && !settings.guestMode
            ? RoutePaths.welcome
            : RoutePaths.latest);

  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.onboarding,
        builder: (context, state) => const OnboardingScreen(),
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
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/anime/:id',
        builder: (context, state) => AnimeDetailsScreen(
          animeId: Uri.decodeComponent(state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/catalog/:kind',
        builder: (context, state) =>
            CatalogScreen(kind: state.pathParameters['kind'] ?? 'newest'),
      ),
      GoRoute(
        path: '/genre/:name',
        builder: (context, state) => GenreScreen(
          genre: Uri.decodeComponent(state.pathParameters['name'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/watch/:animeId/:episodeId',
        builder: (context, state) => PlayerScreen(
          animeId: Uri.decodeComponent(state.pathParameters['animeId'] ?? ''),
          episodeId: Uri.decodeComponent(
            state.pathParameters['episodeId'] ?? '',
          ),
          initialAnime: state.extra is Anime ? state.extra! as Anime : null,
        ),
      ),
      GoRoute(
        path: RoutePaths.downloads,
        builder: (context, state) => const DownloadsScreen(),
      ),
      GoRoute(
        path: RoutePaths.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: RoutePaths.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: RoutePaths.forgot,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: RoutePaths.verify,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: RoutePaths.about,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/legal/:kind',
        builder: (context, state) =>
            LegalScreen(kind: state.pathParameters['kind'] ?? 'privacy'),
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
