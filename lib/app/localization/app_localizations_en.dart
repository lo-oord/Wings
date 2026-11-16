// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Wings';

  @override
  String get navLatest => 'Latest';

  @override
  String get navExplore => 'Explore';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonAll => 'All';

  @override
  String get commonMore => 'More';

  @override
  String get commonSeeAll => 'See all';

  @override
  String get commonShare => 'Share';

  @override
  String get commonDownload => 'Download';

  @override
  String get commonPlay => 'Play';

  @override
  String get commonLoading => 'Loading';

  @override
  String get commonJustNow => 'Just now';

  @override
  String commonMinutesAgo(int count) {
    return '$count minutes ago';
  }

  @override
  String commonHoursAgo(int count) {
    return '$count hours ago';
  }

  @override
  String commonDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String get commonYesterday => 'Yesterday';

  @override
  String get commonErrorTitle => 'Could not complete the request';

  @override
  String get commonEmptyTitle => 'Nothing here yet';

  @override
  String commonEpisodeNumber(int number) {
    return 'Episode $number';
  }

  @override
  String get commonList => 'List';

  @override
  String get commonGrid => 'Grid';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonReset => 'Reset';

  @override
  String get commonSort => 'Sort';

  @override
  String get commonFilter => 'Filter';

  @override
  String get commonType => 'Type';

  @override
  String get commonStatus => 'Status';

  @override
  String get commonYear => 'Year';

  @override
  String get commonGenre => 'Genre';

  @override
  String get commonRating => 'Rating';

  @override
  String get stateErrorNetwork =>
      'Cannot reach the network. Check your connection and try again.';

  @override
  String get stateErrorServer =>
      'The service is temporarily unavailable. Try again shortly.';

  @override
  String get stateErrorNotFound => 'We could not find this content.';

  @override
  String get stateErrorTimeout => 'The request timed out. Please retry.';

  @override
  String get stateErrorGeneric => 'Something went wrong. Please retry.';

  @override
  String get stateOffline => 'You are offline';

  @override
  String get stateOfflineBody =>
      'We will show saved content and resume when you reconnect.';

  @override
  String get homeLatestEpisodes => 'Latest episodes';

  @override
  String get homeRecentlyAdded => 'Recently added';

  @override
  String get homePopular => 'Popular now';

  @override
  String get homeContinueWatching => 'Continue watching';

  @override
  String get homeRecommended => 'You may like';

  @override
  String get homeWatchNow => 'Watch now';

  @override
  String get homeMoreDetails => 'Details';

  @override
  String get homeLatestEmpty => 'No new episodes right now';

  @override
  String get homeNewBadge => 'New';

  @override
  String get homeFeatured => 'Featured';

  @override
  String get homeNextEpisode => 'Next episode';

  @override
  String get exploreTitle => 'Explore';

  @override
  String get exploreSearchHint => 'Search anime...';

  @override
  String get exploreGenres => 'Genres';

  @override
  String get exploreBrowse => 'Browse';

  @override
  String get exploreLatestAdded => 'Recently added';

  @override
  String get exploreTopRated => 'Top rated';

  @override
  String get exploreMostPopular => 'Most popular';

  @override
  String get exploreSort => 'Sort';

  @override
  String get exploreSortNewest => 'Newest';

  @override
  String get exploreSortOldest => 'Oldest';

  @override
  String get exploreSortAz => 'A–Z';

  @override
  String get exploreSortPopular => 'Popularity';

  @override
  String get exploreSortRating => 'Rating';

  @override
  String exploreResults(int count) {
    return '$count results';
  }

  @override
  String get exploreNoResults => 'No matching results';

  @override
  String get exploreFiltersTitle => 'Filters';

  @override
  String get exploreFilterGenre => 'Genre';

  @override
  String get exploreFilterYear => 'Release year';

  @override
  String get exploreFilterStatus => 'Status';

  @override
  String get exploreFilterType => 'Type';

  @override
  String get exploreRandom => 'Random anime';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Anime title in Arabic or English';

  @override
  String get searchRecent => 'Recent searches';

  @override
  String get searchClearAll => 'Clear all';

  @override
  String get searchEmptyTitle => 'Find your anime';

  @override
  String get searchEmptyBody => 'Type a title to find episodes and details.';

  @override
  String get searchNoResults => 'No results';

  @override
  String get searchNoResultsBody => 'Try another title or spelling.';

  @override
  String get searchStartTyping => 'Start typing to search';

  @override
  String get detailsSynopsis => 'Story';

  @override
  String get detailsMore => 'More';

  @override
  String get detailsLess => 'Less';

  @override
  String get detailsInfo => 'Information';

  @override
  String get detailsReleaseDate => 'Release date';

  @override
  String get detailsEpisodesCount => 'Episodes';

  @override
  String get detailsSeason => 'Season';

  @override
  String get detailsStudio => 'Studio';

  @override
  String get detailsStatus => 'Status';

  @override
  String get detailsType => 'Type';

  @override
  String get detailsGenres => 'Genres';

  @override
  String get detailsRating => 'Rating';

  @override
  String get detailsEpisodes => 'Episodes';

  @override
  String get detailsRelated => 'Similar anime';

  @override
  String get detailsAddToLibrary => 'Add to library';

  @override
  String get detailsInLibrary => 'In library';

  @override
  String get detailsShare => 'Share';

  @override
  String get detailsNoEpisodes => 'No episodes are available yet';

  @override
  String get detailsPlanToWatch => 'Plan to watch';

  @override
  String get detailsCompleted => 'Completed';

  @override
  String get detailsOnHold => 'On hold';

  @override
  String get detailsDropped => 'Dropped';

  @override
  String get detailsFavorites => 'Favorites';

  @override
  String get detailsWatching => 'Watching';

  @override
  String get detailsAdded => 'Added to your library';

  @override
  String get detailsRemoved => 'Removed from your library';

  @override
  String get detailsWatch => 'Watch';

  @override
  String get detailsDownloadSheetTitle => 'Download episode';

  @override
  String get detailsDownloadSheetBody =>
      'Pick an available quality to save this episode.';

  @override
  String get detailsNoDownloads => 'No downloadable links for this episode';

  @override
  String get detailsBackdropUnavailable => 'No backdrop available';

  @override
  String get detailsEpisodeWatched => 'Watched';

  @override
  String get playerSpeed => 'Playback speed';

  @override
  String get playerQuality => 'Quality';

  @override
  String get playerNext => 'Next';

  @override
  String get playerPrevious => 'Previous';

  @override
  String get playerServers => 'Servers';

  @override
  String get playerPlaybackError => 'Could not play this episode';

  @override
  String get playerPlaybackErrorBody => 'Try another server or retry.';

  @override
  String get playerLoading => 'Preparing stream...';

  @override
  String get playerNoServers => 'No servers available for this episode';

  @override
  String get playerAutoNextOn => 'Autoplay is on';

  @override
  String get playerAutoNextOff => 'Autoplay is off';

  @override
  String get playerDirect => 'Direct';

  @override
  String get playerOpenInBrowser => 'Open in browser';

  @override
  String get playerSelectServer => 'Choose server';

  @override
  String get playerSubtitles => 'Subtitles';

  @override
  String get playerEpisode => 'Episode';

  @override
  String get playerAutoNext => 'Autoplay next';

  @override
  String get libraryTitle => 'Library';

  @override
  String get libraryFavorites => 'Favorites';

  @override
  String get libraryWatching => 'Watching';

  @override
  String get libraryCompleted => 'Completed';

  @override
  String get libraryPlan => 'Plan to watch';

  @override
  String get libraryOnHold => 'On hold';

  @override
  String get libraryDropped => 'Dropped';

  @override
  String get libraryDownloaded => 'Downloads';

  @override
  String get libraryHistory => 'History';

  @override
  String get libraryEmptyFavorites => 'You have not favorited any anime yet';

  @override
  String get libraryEmptyGeneric =>
      'Your library is empty. Add anime you like.';

  @override
  String get libraryEmptyHistory => 'You have not watched any episode yet';

  @override
  String get libraryClearHistory => 'Clear watch history';

  @override
  String get libraryClearHistoryBody =>
      'Watch history will be permanently removed from this device.';

  @override
  String get libraryRemove => 'Remove from library';

  @override
  String get libraryChangeStatus => 'Change status';

  @override
  String get librarySearchHint => 'Search your library';

  @override
  String get libraryHistoryContinue => 'Continue';

  @override
  String libraryProgress(int percent) {
    return '$percent% watched';
  }

  @override
  String get libraryEmptySearch => 'No matching anime in your library';

  @override
  String get librarySortDate => 'Recently watched';

  @override
  String get librarySortTitle => 'Title';

  @override
  String get downloadsTitle => 'Downloads';

  @override
  String get downloadsActive => 'Downloading';

  @override
  String get downloadsQueued => 'Queued';

  @override
  String get downloadsCompleted => 'Completed';

  @override
  String get downloadsFailed => 'Failed';

  @override
  String get downloadsEmpty => 'No downloads yet';

  @override
  String get downloadsPause => 'Pause';

  @override
  String get downloadsResume => 'Resume';

  @override
  String get downloadsCancel => 'Cancel';

  @override
  String get downloadsRetry => 'Retry';

  @override
  String get downloadsDelete => 'Delete file';

  @override
  String get downloadsStorage => 'Storage used';

  @override
  String get downloadsWifiHint => 'Downloads are best on Wi-Fi';

  @override
  String get downloadsPaused => 'Paused';

  @override
  String get downloadsFailedBody => 'The download could not complete';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsPlayback => 'Playback';

  @override
  String get settingsDefaultSpeed => 'Default speed';

  @override
  String get settingsAutoNext => 'Autoplay next episode';

  @override
  String get settingsRememberPosition => 'Remember playback position';

  @override
  String get settingsDefaultQuality => 'Preferred quality';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsArabic => 'العربية';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotificationsEpisodes => 'New episodes';

  @override
  String get settingsNotificationsDownloads => 'Downloads';

  @override
  String get settingsNotificationsGeneral => 'General';

  @override
  String get settingsEnableAll => 'Enable all';

  @override
  String get settingsDisableAll => 'Disable all';

  @override
  String get settingsPermission => 'Notification permission';

  @override
  String get settingsPermissionGranted => 'Allowed';

  @override
  String get settingsPermissionDenied => 'Not allowed';

  @override
  String get settingsPrivacy => 'Privacy and security';

  @override
  String get settingsClearCache => 'Clear cache';

  @override
  String get settingsClearSearch => 'Clear search history';

  @override
  String get settingsClearHistory => 'Clear watch history';

  @override
  String get settingsAbout => 'About Wings';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get settingsTerms => 'Terms of use';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsSignIn => 'Sign in';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsProfile => 'Profile';

  @override
  String get settingsDownloads => 'Downloads';

  @override
  String get settingsCacheCleared => 'Cache cleared';

  @override
  String get settingsHistoryCleared => 'Watch history cleared';

  @override
  String get settingsSearchCleared => 'Search history cleared';

  @override
  String get settingsConfirmClearTitle => 'Are you sure?';

  @override
  String get settingsGuest => 'Guest';

  @override
  String get settingsOpenSource => 'Open source';

  @override
  String get settingsStorage => 'Download storage';

  @override
  String get authWelcomeTitle => 'Welcome to Wings';

  @override
  String get authWelcomeBody =>
      'Follow your favorite anime, save episodes, and resume where you left off.';

  @override
  String get authLogin => 'Sign in';

  @override
  String get authRegister => 'Create account';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authConfirmPassword => 'Confirm password';

  @override
  String get authName => 'Name';

  @override
  String get authForgot => 'Forgot password?';

  @override
  String get authRemember => 'Remember me';

  @override
  String get authNoAccount => 'No account?';

  @override
  String get authHaveAccount => 'Already have an account?';

  @override
  String get authSendReset => 'Send reset link';

  @override
  String get authBackToLogin => 'Back to sign in';

  @override
  String get authVerifyTitle => 'Verify your email';

  @override
  String get authVerifyBody =>
      'We sent a verification link to your email. Open it to continue.';

  @override
  String get authUnavailable => 'Cloud account not enabled';

  @override
  String get authUnavailableBody =>
      'Account screens are ready but awaiting an authentication service. You can use Wings as a guest now.';

  @override
  String get authContinueGuest => 'Continue as guest';

  @override
  String get authValidationEmail => 'Enter a valid email';

  @override
  String get authValidationPassword => 'Password must be at least 8 characters';

  @override
  String get authValidationName => 'Enter a name of at least 2 characters';

  @override
  String get authValidationConfirm => 'Passwords do not match';

  @override
  String get authAcceptTerms =>
      'I agree to the terms of use and privacy policy';

  @override
  String get authResetSent =>
      'If the email is registered, a reset link is on its way.';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileGuest => 'Guest account';

  @override
  String get profileEdit => 'Edit profile';

  @override
  String get profileStats => 'Your stats';

  @override
  String get profileFavorites => 'Favorites';

  @override
  String get profileCompleted => 'Completed';

  @override
  String get profileWatching => 'Watching';

  @override
  String get profileDownloads => 'Downloads';

  @override
  String get profileMemberSince => 'Member since';

  @override
  String get profileSignInPrompt =>
      'Sign in to sync your library across devices.';

  @override
  String get profileDeleteAccount => 'Delete account';

  @override
  String get profileDeleteBody =>
      'Your account and cloud data will be deleted. Local data stays until you clear it.';

  @override
  String get profileDeleteDone => 'Account deleted';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsMarkAll => 'Mark all as read';

  @override
  String get notificationsEmpty => 'No notifications';

  @override
  String get notificationsSettings => 'Notification settings';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingStart => 'Get started';

  @override
  String get onboardingTitle1 => 'Discover your anime';

  @override
  String get onboardingBody1 =>
      'New episodes, seasonal titles and top-rated shows in one place.';

  @override
  String get onboardingTitle2 => 'Watch in the best quality';

  @override
  String get onboardingBody2 =>
      'A fast player with quality and speed control that remembers your place.';

  @override
  String get onboardingTitle3 => 'Your library, with you';

  @override
  String get onboardingBody3 =>
      'Favorite, download, and continue from where you stopped any time.';

  @override
  String genreTitle(String name) {
    return 'Genre: $name';
  }

  @override
  String get genreEmpty => 'Nothing in this genre';

  @override
  String get statusOngoing => 'Ongoing';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get typeSeries => 'Series';

  @override
  String get typeMovie => 'Movie';

  @override
  String get errorNoEpisodes => 'No episodes';

  @override
  String get searchHistoryRemoved => 'Removed from history';

  @override
  String get commonNext => 'Next';

  @override
  String get commonBack => 'Back';

  @override
  String get authUsername => 'Username';

  @override
  String get authValidationUsername => '3–20 letters, numbers or underscores';

  @override
  String get authCountry => 'Country';

  @override
  String get authChoosePhoto => 'Change photo';

  @override
  String authStepOf(String current, String total) {
    return 'Step $current of $total';
  }

  @override
  String get authPasswordWeak => 'Weak';

  @override
  String get authPasswordMedium => 'Fair';

  @override
  String get authPasswordStrong => 'Strong';

  @override
  String notificationsEpisodeBody(int number) {
    return 'Episode $number is now available 🎉 Tap to watch';
  }
}
