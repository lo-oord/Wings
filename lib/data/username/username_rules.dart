import 'package:flutter/foundation.dart';

enum UsernameProblem { empty, tooShort, tooLong, invalidCharacters, reserved }

/// Validation, normalization and suggestion rules for user handles.
///
/// The normalized value (trimmed, lower-case) is the uniqueness key used by the
/// `usernames/{normalized}` reservation documents, so `Lord_Shadow` and
/// `lord_shadow` can never both be taken.
abstract final class UsernameRules {
  static const int minLength = 3;
  static const int maxLength = 20;

  static final RegExp _allowed = RegExp(r'^[a-z0-9_]+$');

  /// Names kept for system accounts and administrative functions.
  static const Set<String> reserved = <String>{
    'admin',
    'administrator',
    'wings',
    'wings_app',
    'support',
    'moderator',
    'mod',
    'staff',
    'system',
    'root',
    'owner',
    'developer',
    'official',
    'help',
    'settings',
    'profile',
    'null',
    'undefined',
    'deleted',
  };

  static String normalize(String raw) => raw.trim().toLowerCase();

  /// Strips everything the username charset does not allow, used to build
  /// suggestions from whatever the user typed.
  static String sanitize(String raw) =>
      normalize(raw).replaceAll(RegExp('[^a-z0-9_]'), '');

  static UsernameValidation validate(String raw) {
    final normalized = normalize(raw);
    if (normalized.isEmpty) {
      return UsernameValidation._(normalized, UsernameProblem.empty);
    }
    if (normalized.length < minLength) {
      return UsernameValidation._(normalized, UsernameProblem.tooShort);
    }
    if (normalized.length > maxLength) {
      return UsernameValidation._(normalized, UsernameProblem.tooLong);
    }
    if (!_allowed.hasMatch(normalized)) {
      return UsernameValidation._(
        normalized,
        UsernameProblem.invalidCharacters,
      );
    }
    if (reserved.contains(normalized)) {
      return UsernameValidation._(normalized, UsernameProblem.reserved);
    }
    return UsernameValidation._(normalized, null);
  }

  /// Builds deterministic, on-brand alternatives close to [raw]. The caller
  /// still has to check each candidate for availability.
  static List<String> suggestions(String raw, {int count = 4}) {
    final base = sanitize(raw);
    final seed = base.isEmpty ? 'wings' : base;
    final stem = seed.length > maxLength - 6
        ? seed.substring(0, maxLength - 6)
        : seed;
    final digits = 100 + (stem.hashCode.abs() % 900);
    final candidates = <String>[
      '${stem}_wings',
      '${stem}_07',
      '${stem}_x7',
      '${stem}_$digits',
      '${stem}_anime',
      '${stem}_${DateTime.now().year}',
    ];
    final seen = <String>{seed};
    final result = <String>[];
    for (final candidate in candidates) {
      final normalized = normalize(candidate);
      if (normalized.length > maxLength) continue;
      if (normalized.length < minLength) continue;
      if (!seen.add(normalized)) continue;
      if (!validate(normalized).ok) continue;
      result.add(normalized);
      if (result.length >= count) break;
    }
    return result;
  }
}

@immutable
class UsernameValidation {
  const UsernameValidation._(this.normalized, this.problem);

  final String normalized;
  final UsernameProblem? problem;

  bool get ok => problem == null;
}
