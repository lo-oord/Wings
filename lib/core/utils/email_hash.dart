import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Normalized SHA-256 of an email address.
///
/// The same value is used by the registration rule and by the owner denylist,
/// so `emailBlocks/{hash}` never stores or exposes a raw address. Trimming and
/// lower-casing happen here once, which is what makes the check immune to case
/// and whitespace variations.
String hashEmail(String email) =>
    sha256.convert(utf8.encode(email.trim().toLowerCase())).toString();
