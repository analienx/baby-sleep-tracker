import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_emulator_host.dart';

import '../features/family/data/family_client.dart';

const bool useFamilyEmulator = bool.fromEnvironment('USE_FAMILY_EMULATOR');
const bool useFamilyProduction = bool.fromEnvironment('USE_FAMILY_PRODUCTION');

/// No default build can connect to real child data. Firebase application
/// identifiers are environment-specific (public identifiers, not credentials).
/// Supply production values using a local ignored dart-define file.
Future<FamilyClient> connectFamily() async {
  if (useFamilyEmulator == useFamilyProduction) {
    throw StateError('Choose exactly one Firebase family environment.');
  }
  if (useFamilyEmulator &&
      (kReleaseMode || (!Platform.isAndroid && !Platform.isIOS))) {
    throw StateError('Family emulators require a debug mobile build.');
  }

  final app = await Firebase.initializeApp(
    options: useFamilyEmulator
        ? FirebaseOptions(
            apiKey: demoFirebaseApiKey,
            appId: Platform.isIOS
                ? '1:1234567890:ios:1234567890123456'
                : '1:1234567890:android:1234567890123456',
            messagingSenderId: '1234567890',
            projectId: 'demo-little-rest',
          )
        : _productionOptions(),
  );
  if (useFamilyProduction) {
    // Must run before Auth/Firestore/Functions. Neither debug-provider tokens
    // nor a bypass flag can be used with a production build.
    await FirebaseAppCheck.instanceFor(app: app).activate(
      providerAndroid: const AndroidPlayIntegrityProvider(),
      providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  }
  final auth = FirebaseAuth.instanceFor(app: app);
  final firestore = FirebaseFirestore.instanceFor(app: app);
  firestore.settings = const Settings(persistenceEnabled: true);
  final functions = FirebaseFunctions.instanceFor(
    app: app,
    region: 'europe-west1',
  );
  if (useFamilyEmulator) {
    final host = resolveFirebaseEmulatorHost(
      isAndroid: Platform.isAndroid,
      configuredHost: configuredFirebaseEmulatorHost,
      isRelease: kReleaseMode,
    );
    await auth.useAuthEmulator(host, 9099);
    firestore.useFirestoreEmulator(host, 8080);
    functions.useFunctionsEmulator(host, 5001);
  }
  if (auth.currentUser == null) {
    await auth.signInAnonymously();
  }
  return FamilyClient(auth: auth, firestore: firestore, functions: functions);
}

FirebaseOptions _productionOptions() {
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  // Firebase generates independently restricted API keys for Android and iOS.
  const androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  const iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const androidApp = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  const iosApp = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  const iosBundle = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  if ([
    project,
    androidApiKey,
    iosApiKey,
    sender,
    androidApp,
    iosApp,
    iosBundle,
  ].any((value) => value.isEmpty)) {
    throw StateError(
      'Production Firebase identifiers missing. Check dart defines.',
    );
  }
  return FirebaseOptions(
    projectId: project,
    apiKey: Platform.isIOS ? iosApiKey : androidApiKey,
    messagingSenderId: sender,
    appId: Platform.isIOS ? iosApp : androidApp,
    iosBundleId: Platform.isIOS ? iosBundle : null,
  );
}
