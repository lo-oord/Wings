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

  /// The system "remove animations" switch. Decorative motion collapses to zero
  /// while functional transitions keep their final state.
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);

  /// A duration that honours [reduceMotion].
  Duration motionDuration(Duration duration) =>
      reduceMotion ? Duration.zero : duration;

  /// One snackbar style for the whole app: floating, rounded, iconed, and long
  /// enough to read for a failure but short for a confirmation. A new message
  /// replaces the previous one instead of stacking behind it.
  void showSnack(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.maybeOf(this);
    if (messenger == null) return;
    final background = isError ? palette.danger : palette.surfaceHigh;
    final foreground = isError ? palette.onPrimary : palette.textPrimary;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: Duration(milliseconds: isError ? 4000 : 2400),
          backgroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: isError ? BorderSide.none : BorderSide(color: palette.border),
          ),
          content: Row(
            children: <Widget>[
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 18,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: foreground, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
