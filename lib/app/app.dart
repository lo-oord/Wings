import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/wings_feedback.dart';
import 'localization/app_localizations.dart';
import 'providers.dart';
import 'router/app_router.dart';
import 'scroll_behavior.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';

class WingsApp extends ConsumerStatefulWidget {
  const WingsApp({super.key});

  @override
  ConsumerState<WingsApp> createState() => _WingsAppState();
}

class _WingsAppState extends ConsumerState<WingsApp>
    with WidgetsBindingObserver {
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = ref.read(notificationServiceProvider);
    notifications.taps.listen(_openPayload);
    final cold = notifications.takeColdPayload();
    if (cold != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPayload(cold));
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(notificationsProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _openPayload(String payload) {
    final router = _router;
    if (payload.isEmpty || router == null) return;
    router.push(payload);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(notificationsProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    _router = router;

    return MaterialApp.router(
      title: 'Wings',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildWingsTheme(WingsPalette.light),
      darkTheme: buildWingsTheme(WingsPalette.dark),
      themeMode: settings.themeMode,
      scrollBehavior: const WingsScrollBehavior(),
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) {
        // The interface is designed for a restrained text scale range so
        // layouts stay intact on devices with large accessibility fonts.
        final media = MediaQuery.of(context);
        final scale = media.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: media.copyWith(textScaler: scale),
          child: child ?? const WingsLoading(),
        );
      },
    );
  }
}
