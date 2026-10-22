import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'family_bootstrap.dart';
import 'web_storage_probe.dart';
import 'firebase_emulator_host.dart';
import '../features/personal/data/personal_cloud_client.dart';

/// Deliberately opt-in. Real Spark staging is debug-only until G2/G3 approval.
/// Family cloud mode continues to require the separately reviewed callables.
const usePersonalStaging = bool.fromEnvironment('USE_PERSONAL_STAGING');
const usePersonalEmulator = bool.fromEnvironment('USE_PERSONAL_EMULATOR');
// Optional Spark Family Lite rollout; disabled for live staging until Rule QA.
const useSparkFamilyLite = bool.fromEnvironment('USE_SPARK_FAMILY_LITE');
// Explicit, separately deployed iPhone Home Screen PWA; Android is unchanged.
const useIosPwa = bool.fromEnvironment('USE_IOS_PWA');

Future<PersonalCloudClient> connectPersonalCloud() async {
  if (usePersonalStaging == usePersonalEmulator ||
      (kIsWeb && (!useIosPwa || !useSparkFamilyLite)) ||
      (!kIsWeb && (kReleaseMode || (!Platform.isAndroid && !Platform.isIOS)))) {
    throw StateError(
      'Personal cloud is only available in an explicit mobile debug build.',
    );
  }

  if (kIsWeb && !await canPersistWebData()) {
    throw StateError(
      'Safari cannot use IndexedDB on this device. '
      'Do not record sleep until browser storage is enabled.',
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
  if (kIsWeb) {
    // App Check is configured only when Firebase Console has registered the
    // matching reCAPTCHA Enterprise site key. No production claims without it.
    const siteKey = String.fromEnvironment('FIREBASE_WEB_APPCHECK_SITE_KEY');
    if (siteKey.isNotEmpty) {
      await FirebaseAppCheck.instanceFor(app: app)
          .activate(providerWeb: ReCaptchaEnterpriseProvider(siteKey));
    }
  }
  final auth = FirebaseAuth.instanceFor(app: app);
  if (kIsWeb) {
    // Home Screen apps need the same recoverable Auth UID across relaunches.
    await auth.setPersistence(Persistence.LOCAL);
  }
  final firestore = FirebaseFirestore.instanceFor(app: app);
  if (kIsWeb) {
    // FlutterFire 7 configures persistent IndexedDB via Settings rather than
    // the removed enablePersistence method. Shared tabs avoid lock failures.
    // Safari may still evict site storage: UI must not promise guaranteed
    // offline durability; physical-device QA must verify the storage path.
    firestore.settings = const Settings(
      persistenceEnabled: true,
      webPersistentTabManager: WebPersistentMultipleTabManager(),
    );
  } else {
    firestore.settings = const Settings(persistenceEnabled: true);
  }

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
  // On the web, wait until Firebase has restored its persistent identity
  // before making any anonymous account. Otherwise Safari's first frame may
  // race the saved login and silently create a different journal.
  final User? restoredUser;
  if (kIsWeb) {
    restoredUser = await auth.authStateChanges().first;
  } else {
    restoredUser = auth.currentUser;
  }
  if (restoredUser == null) {
    await auth.signInAnonymously();
  }
  return PersonalCloudClient(
    auth: auth,
    firestore: firestore,
    familyLiteEnabled: useSparkFamilyLite,
  );
}
