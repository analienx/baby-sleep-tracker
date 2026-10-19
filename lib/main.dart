import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/emulator_bootstrap.dart';
import 'app/family_bootstrap.dart';
import 'app/providers.dart';
import 'features/family/presentation/family_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (useFirebaseEmulator && (useFamilyEmulator || useFamilyProduction)) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Choose exactly one storage environment.')),
        ),
      ),
    );
    return;
  }
  if (useFamilyEmulator || useFamilyProduction) {
    try {
      final familyClient = await connectFamily();
      runApp(FamilyGate(client: familyClient));
    } catch (error) {
      runApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Family service unavailable. No sleep data was recorded. $error',
                ),
              ),
            ),
          ),
        ),
      );
    }
    return;
  }
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
                    'Development emulators unavailable. '
                    'No sleep data was recorded. Start Auth and Firestore emulators.',
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
