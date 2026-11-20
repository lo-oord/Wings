import 'package:flutter/widgets.dart';

import '../../data/auth/auth_error_text.dart';
import '../utils/tr.dart';

/// One place that turns any failure into copy a member can read.
///
/// Nothing technical (Firebase, Firestore, rules, project ids, plugin names)
/// may reach the interface: those details belong in logs, never in a snack bar.
String userFacingError(BuildContext context, Object error) =>
    authErrorText(context, error);

/// Copy shown when a background list cannot be loaded.
String loadFailedText(BuildContext context) => Tr.of(
  context,
  ar: 'تعذر تحميل البيانات. تحقق من اتصالك وحاول مجددًا.',
  en: 'Could not load the data. Check your connection and try again.',
);
