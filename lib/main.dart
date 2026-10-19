import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/emulator_bootstrap.dart';
import 'app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (useFirebaseEmulator) {
    try {
      final repository = await connectToDevelopmentEmulators();
      runApp(
        ProviderScope(
          overrides: [sleepRepositoryProvider.overrideWithValue(repository)],
          child: const BabySleepApp(),
        ),
      );
    } catch (_) {
      runApp(
        const MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'The development emulators are unavailable. '
                    'No sleep data was recorded. Start Auth and Firestore '
                    'emulators, then restart the app.',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return;
  }
  runApp(const ProviderScope(child: BabySleepApp()));
}
