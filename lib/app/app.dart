import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/wings_feedback.dart';
import 'localization/app_localizations.dart';
import 'providers.dart';
import 'router/app_router.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';

class WingsApp extends ConsumerWidget {
  const WingsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Wings',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildWingsTheme(WingsPalette.light),
      darkTheme: buildWingsTheme(WingsPalette.dark),
      themeMode: settings.themeMode,
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
