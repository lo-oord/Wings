import 'package:flutter/widgets.dart';

/// Inline bilingual copy for the account and social surfaces.
///
/// The original screens use generated ARB localizations. New strings live here
/// so Arabic and English stay in sync without regenerating the ARB files for
/// every small addition.
abstract final class Tr {
  static bool isArabic(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar';

  static String of(
    BuildContext context, {
    required String ar,
    required String en,
  }) => isArabic(context) ? ar : en;
}
