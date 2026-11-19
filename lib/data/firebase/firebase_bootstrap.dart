import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Initializes Firebase and waits briefly for the persisted session.
///
/// Android reads the configuration from `android/app/google-services.json`;
/// no credentials are compiled into Dart. Offline persistence is enabled so the
/// library and profiles stay usable without a connection.
///
/// Returns false when Firebase is not configured (for example a developer
/// build without the config file). The app then falls back to the local-only
/// adapter instead of crashing.
Future<bool> initializeFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    // The persisted session arrives through the auth stream and is applied as
    // soon as it lands. Waiting for that first event only prevents the router
    // from briefly flashing the sign-in gate, so the wait is bounded to a
    // fraction of a second instead of the three seconds this used to cost on
    // every launch.
    try {
      await FirebaseAuth.instance.authStateChanges().first.timeout(
        const Duration(milliseconds: 900),
      );
    } on Object {
      // A slow restore must not block start-up; the auth stream still updates
      // the session as soon as it arrives.
    }
    return true;
  } on Object catch (error) {
    debugPrint('Firebase initialization failed: $error');
    return false;
  }
}
