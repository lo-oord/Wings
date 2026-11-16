import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import 'app_palette.dart';

extension WingsContext on BuildContext {
  WingsPalette get palette => Theme.of(this).extension<WingsPalette>()!;

  TextTheme get text => Theme.of(this).textTheme;

  ColorScheme get colors => Theme.of(this).colorScheme;

  AppLocalizations get l10n => AppLocalizations.of(this);

  bool get isRtl => Directionality.of(this) == TextDirection.rtl;

  double get pageWidth => MediaQuery.sizeOf(this).width;

  bool get isCompact => pageWidth < 600;

  void showSnack(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.maybeOf(this);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? palette.danger : null,
        ),
      );
  }
}
