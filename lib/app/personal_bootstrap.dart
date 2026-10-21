import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'family_bootstrap.dart';
import 'firebase_emulator_host.dart';
import '../features/personal/data/personal_cloud_client.dart';

/// Deliberately opt-in. Real Spark staging is debug-only until G2/G3 approval.
/// Family cloud mode continues to require the separately reviewed callables.
const usePersonalStaging = bool.fromEnvironment('USE_PERSONAL_STAGING');
const usePersonalEmulator = bool.fromEnvironment('USE_PERSONAL_EMULATOR');

Future<PersonalCloudClient> connectPersonalCloud() async {
  if (usePersonalStaging == usePersonalEmulator ||
      kReleaseMode ||
      (!Platform.isAndroid && !Platform.isIOS)) {
    throw StateError(
      'Personal cloud is only available in an explicit mobile debug build.',
    );
  }

  final app = await Firebase.initializeApp(
    options: usePersonalEmulator
        ? FirebaseOptions(
            apiKey: demoFirebaseApiKey,
            appId: Platform.isIOS
                ? '1:1234567890:ios:1234567890123456'
                : '1:1234567890:android:1234567890123456',
            messagingSenderId: '1234567890',
            projectId: 'demo-little-rest',
          )
        : configuredFirebaseOptions(),
  );
  final auth = FirebaseAuth.instanceFor(app: app);
  final firestore = FirebaseFirestore.instanceFor(app: app);
  firestore.settings = const Settings(persistenceEnabled: true);

  if (usePersonalEmulator) {
    final host = resolveFirebaseEmulatorHost(
      isAndroid: Platform.isAndroid,
      configuredHost: configuredFirebaseEmulatorHost,
      isRelease: kReleaseMode,
    );
    await auth.useAuthEmulator(host, 9099);
    firestore.useFirestoreEmulator(host, 8080);
  }

  // Firebase Auth retains this UID across application restarts. An initial
  // installation needs connectivity; later launches use the saved identity.
  if (auth.currentUser == null) {
    await auth.signInAnonymously();
  }
  return PersonalCloudClient(auth: auth, firestore: firestore);
}
