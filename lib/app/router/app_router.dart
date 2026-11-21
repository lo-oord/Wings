import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/anime.dart';
import '../../features/account_status/account_status_screen.dart';
import '../../features/admin/admin_announcements_screen.dart';
import '../../features/admin/admin_home_screen.dart';
import '../../features/admin/admin_log_screen.dart';
import '../../features/admin/admin_messages_screen.dart';
import '../../features/admin/admin_monitor_screen.dart';
import '../../features/admin/admin_policies_screen.dart';
import '../../features/admin/admin_providers.dart';
import '../../features/admin/admin_reports_screen.dart';
import '../../features/admin/admin_user_screen.dart';
import '../../features/admin/admin_users_screen.dart';
import '../../features/admin/owner_message_screen.dart';
import '../../features/auth/auth_screens.dart';
import '../../features/auth/complete_profile_screen.dart';
import '../../features/community/community_screen.dart';
import '../../features/community/community_search_screen.dart';
import '../../features/community/people_screen.dart';
import '../../features/community/post_composer_screen.dart';
import '../../features/community/reel_composer_screen.dart';
import '../../features/community/post_detail_screen.dart';
import '../../features/chat/chat_privacy_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/chats_screen.dart';
import '../../features/chat/new_chat_screen.dart';
import '../../features/community/reels_screen.dart';
import '../../features/community/saved_posts_screen.dart';
import '../../features/details/anime_details_screen.dart';
import '../../features/downloads/downloads_screen.dart';
import '../../features/explore/catalog_screen.dart';
import '../../features/explore/explore_screen.dart';
import '../../features/explore/genre_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/live/live_player_screen.dart';
import '../../data/models/live_channel.dart';
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
    // The redirect decides whether the account still needs a profile, so it
    // must re-run when the profile arrives or is created.
    ref.listen(profileProvider, (_, _) => notifyListeners());
    ref.listen(profileResolvedProvider, (_, _) => notifyListeners());
    // A suspension, ban or deletion applied from the console takes effect on the
    // next status refresh instead of waiting for a restart.
    ref.listen(myAccountStatusProvider, (_, _) => notifyListeners());
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
    if (account != null) {
      // Developer tools are Owner-only. A direct navigation by anyone else goes
      // back to a safe screen; the screens and the server re-check the role.
      if (location.startsWith('/admin')) {
        final role = ref.read(staffRoleProvider).value;
        if (role != null && !role.isAdmin) return RoutePaths.settings;
      }
      // A locked account can only read its own status page. The rules refuse
      // its writes independently of this check.
      final status = ref.read(myAccountStatusProvider).value;
      if (status != null &&
          status.isLockedAt(DateTime.now()) &&
          location != RoutePaths.accountStatus) {
        return RoutePaths.accountStatus;
      }
      // An email + password account cannot move on before the address is
      // confirmed; the verification screen is the only place it may stay.
      if (account.hasPassword && !account.emailVerified) {
        return location == RoutePaths.verify ? null : RoutePaths.verify;
      }
      final resolved = ref.read(profileResolvedProvider);
      final hasProfile = ref.read(profileProvider) != null;
      // A Google sign-up that has not chosen its username yet finishes here.
      if (resolved && !hasProfile) {
        return location == RoutePaths.complete ? null : RoutePaths.complete;
      }
      if (hasProfile && location == RoutePaths.complete) {
        return RoutePaths.latest;
      }
      if (location == RoutePaths.welcome) return RoutePaths.latest;
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
                path: RoutePaths.community,
                builder: (context, state) => const CommunityScreen(),
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
                builder: (context, state) => LibraryScreen(
                  initialTab:
                      int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
                ),
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
        path: '/live/:id',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          LivePlayerScreen(
            channelId: Uri.decodeComponent(state.pathParameters['id'] ?? ''),
            channel: state.extra is LiveChannel
                ? state.extra! as LiveChannel
                : null,
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
        path: '/user/:uid/followers',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          PeopleScreen(
            uid: Uri.decodeComponent(state.pathParameters['uid'] ?? ''),
            kind: PeopleListKind.followers,
          ),
        ),
      ),
      GoRoute(
        path: '/user/:uid/following',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          PeopleScreen(
            uid: Uri.decodeComponent(state.pathParameters['uid'] ?? ''),
            kind: PeopleListKind.following,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.communitySearch,
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          CommunitySearchScreen(
            initialQuery: state.uri.queryParameters['q'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/community/tag/:slug',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          CommunitySearchScreen(
            initialQuery:
                '#${Uri.decodeComponent(state.pathParameters['slug'] ?? '')}',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.communityCompose,
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          PostComposerScreen(
            seed: state.extra is PostComposerSeed
                ? state.extra! as PostComposerSeed
                : null,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.communityReelCompose,
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          ReelComposerScreen(
            seed: state.extra is ReelComposerSeed
                ? state.extra! as ReelComposerSeed
                : null,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.chats,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const ChatsScreen()),
      ),
      GoRoute(
        path: RoutePaths.chatNew,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const NewChatScreen()),
      ),
      GoRoute(
        path: RoutePaths.chatPrivacy,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const ChatPrivacyScreen()),
      ),
      GoRoute(
        path: '/chats/:chatId',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          ChatScreen(
            chatId: Uri.decodeComponent(state.pathParameters['chatId'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.communityReels,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const ReelsScreen()),
      ),
      GoRoute(
        path: RoutePaths.communitySaved,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const SavedPostsScreen()),
      ),
      GoRoute(
        path: '/community/post/:postId',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          PostDetailScreen(
            postId: Uri.decodeComponent(state.pathParameters['postId'] ?? ''),
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
        path: RoutePaths.complete,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const CompleteProfileScreen()),
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
      // -------------------------------------------------- developer tools
      GoRoute(
        path: RoutePaths.admin,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AdminHomeScreen()),
      ),
      GoRoute(
        path: RoutePaths.adminUsers,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AdminUsersScreen()),
      ),
      GoRoute(
        path: '/admin/users/:uid',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          AdminUserScreen(
            uid: Uri.decodeComponent(state.pathParameters['uid'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.adminPolicies,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AdminPoliciesScreen()),
      ),
      GoRoute(
        path: RoutePaths.adminReports,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AdminReportsScreen()),
      ),
      GoRoute(
        path: RoutePaths.adminMessages,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AdminMessagesScreen()),
      ),
      GoRoute(
        path: RoutePaths.adminAnnouncements,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AdminAnnouncementsScreen()),
      ),
      GoRoute(
        path: RoutePaths.adminMonitor,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AdminMonitorScreen()),
      ),
      GoRoute(
        path: RoutePaths.adminLog,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AdminLogScreen()),
      ),
      GoRoute(
        path: RoutePaths.accountStatus,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const AccountStatusScreen()),
      ),
      GoRoute(
        path: RoutePaths.ownerMessages,
        pageBuilder: (context, state) =>
            _wingsPage(context, state, const OwnerInboxScreen()),
      ),
      GoRoute(
        path: '/owner-message/:id',
        pageBuilder: (context, state) => _wingsPage(
          context,
          state,
          OwnerMessageScreen(
            messageId: Uri.decodeComponent(state.pathParameters['id'] ?? ''),
          ),
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
