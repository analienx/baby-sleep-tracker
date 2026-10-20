import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_emulator_host.dart';

import '../features/sleep/data/firestore_sleep_repository.dart';

/// Compile-time opt-in with --dart-define=USE_FIREBASE_EMULATOR=true.
/// This build has NO production Firebase config or keys.
const bool useFirebaseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

Future<FirestoreSleepRepository> connectToDevelopmentEmulators() async {
  if (!useFirebaseEmulator ||
      kReleaseMode ||
      (!Platform.isIOS && !Platform.isAndroid)) {
    throw StateError(
      'Firebase demo mode is permitted only on debug mobile builds.',
    );
  }
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: demoFirebaseApiKey,
      appId: Platform.isIOS
          ? '1:1234567890:ios:1234567890123456'
          : '1:1234567890:android:1234567890123456',
      messagingSenderId: '1234567890',
      projectId: 'demo-little-rest',
    ),
  );

  final host = resolveFirebaseEmulatorHost(
    isAndroid: Platform.isAndroid,
    configuredHost: configuredFirebaseEmulatorHost,
    isRelease: kReleaseMode,
  );
  final auth = FirebaseAuth.instance;
  await auth.useAuthEmulator(host, 9099);
  final firestore = FirebaseFirestore.instance;
  firestore.settings = const Settings(persistenceEnabled: true);
  firestore.useFirestoreEmulator(host, 8080);

  // A persistent anonymous *emulator* account supports offline relaunch after
  // first sign-in. First-time onboarding necessarily needs the Auth emulator.
  final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
  if (user == null) throw StateError('Could not start synthetic demo account.');
  return FirestoreSleepRepository(
    firestore: firestore,
    syntheticUserId: user.uid,
  );
}
