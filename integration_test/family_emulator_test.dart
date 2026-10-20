import 'dart:convert';
import 'dart:io';

import 'package:baby_sleep_tracker/app/family_bootstrap.dart';
import 'package:baby_sleep_tracker/features/family/data/family_client.dart';
import 'package:baby_sleep_tracker/features/family/presentation/family_gate.dart';
import 'package:baby_sleep_tracker/main.dart' as application;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs as a REAL mobile Flutter app against the local Firebase emulators.
/// Never execute with a real Firebase project or personal sleep records.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // This endpoint exists only in Firebase's local Auth Emulator. Following a
  // real verification code keeps the integration test aligned with production
  // invitation policy, without weakening email verification in the app.
  Future<void> verifyEmulatedEmail(
    FirebaseAuth auth,
    String email,
    String host,
  ) async {
    await auth.currentUser!.sendEmailVerification();
    final client = HttpClient();
    try {
      final url = Uri.parse(
        'http://$host:9099/emulator/v1/projects/demo-little-rest/oobCodes',
      );
      final response = await (await client.getUrl(url)).close();
      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(
        await response.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      final codes = (body['oobCodes'] as List).cast<Map<String, dynamic>>();
      final code =
          codes.lastWhere(
                (entry) =>
                    entry['email'] == email &&
                    entry['requestType'] == 'VERIFY_EMAIL',
              )['oobCode']
              as String;
      await auth.applyActionCode(code);
      await auth.currentUser!.reload();
      await auth.currentUser!.getIdToken(true);
      expect(auth.currentUser!.emailVerified, isTrue);
    } finally {
      client.close(force: true);
    }
  }

  testWidgets('persistent family UI: offline write, relaunch, second caregiver', (
    tester,
  ) async {
    expect(useFamilyEmulator, isTrue, reason: 'Not a preview-mode test');
    expect(useFamilyProduction, isFalse);

    Future<void> until(Finder finder, String purpose) async {
      final deadline = DateTime.now().add(const Duration(seconds: 70));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 250));
        if (finder.evaluate().isNotEmpty) return;
        if (purpose == 'family Today' &&
            find.byType(SelectableText).evaluate().isNotEmpty) {
          final errors = find
              .byType(SelectableText)
              .evaluate()
              .map((element) => (element.widget as SelectableText).data ?? '')
              .toList();
          throw TestFailure('Create family failed: $errors');
        }
      }
      // Preserve the user-visible error when a Firebase callable fails. In an
      // instrumented device run a bare timeout otherwise hides the actual
      // reason (e.g. missing Auth state, denied Rules, unreachable Functions).
      final visible = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .where((value) => value.isNotEmpty)
          .take(35)
          .join(' | ');
      final frameworkError = tester.takeException();
      throw TestFailure(
        'Timed out: $purpose. Visible UI: $visible. '
        'Flutter error: ${frameworkError ?? 'none'}',
      );
    }

    await application.main();
    await until(find.text('Create family'), 'Auth emulator onboarding');
    await tester.enterText(find.byType(TextField).first, 'Synthetic Infant');
    await tester.tap(find.text('Create family'));
    await until(find.text('Start sleep'), 'family Today');
    expect(find.text('FAMILY DEV'), findsOneWidget);

    final primaryApp = Firebase.app();
    final auth = FirebaseAuth.instanceFor(app: primaryApp);
    final db = FirebaseFirestore.instanceFor(app: primaryApp);
    final functions = FirebaseFunctions.instanceFor(
      app: primaryApp,
      region: 'europe-west1',
    );
    final uid = auth.currentUser!.uid;
    final userDoc = await db
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    final family = FamilyContext.fromData(userDoc.data())!;
    final path =
        'families/${family.familyId}/babies/${family.babyId}/operations';
    final operations = db.collection(path);

    // Firestore native local persistent cache must work with backend disabled.
    await db.disableNetwork();
    await tester.tap(find.text('Start sleep').first);
    await until(find.text('Wake up'), 'local cache acknowledged Start');
    final cached = await operations.get(const GetOptions(source: Source.cache));
    expect(cached.docs.length, 1);
    expect(cached.docs.single.metadata.hasPendingWrites, isTrue);
    final startId = cached.docs.single.id;

    // Recreate widget tree and repository while network remains disabled.
    // This is NOT equivalent to an OS force-stop/reboot (physical QA pending).
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Reattaching'))),
    );
    await tester.pumpWidget(
      FamilyGate(
        client: FamilyClient(auth: auth, firestore: db, functions: functions),
      ),
    );
    await until(find.text('Wake up'), 'restored local sleep');

    await db.enableNetwork();
    // A server-sourced get can return documents that still carry locally
    // pending writes. The offline operation is durable only after Firestore
    // confirms the complete queue was sent and acknowledged.
    await db.waitForPendingWrites().timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TestFailure(
        'Firestore did not acknowledge the queued offline sleep operation',
      ),
    );
    final confirmed = await operations.get(
      const GetOptions(source: Source.server),
    );
    expect(confirmed.docs.length, 1, reason: 'no duplicate after replay');
    expect(confirmed.docs.single.id, startId);
    expect(confirmed.docs.single.metadata.hasPendingWrites, isFalse);

    const host = String.fromEnvironment(
      'FIREBASE_EMULATOR_HOST',
      defaultValue: '10.0.2.2',
    );
    expect(host, isNotEmpty);
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final ownerEmail = 'owner-$nonce@example.test';
    await auth.currentUser!.linkWithCredential(
      EmailAuthProvider.credential(
        email: ownerEmail,
        password: 'test-password-123',
      ),
    );
    await verifyEmulatedEmail(auth, ownerEmail, host);
    final owner = FamilyClient(auth: auth, firestore: db, functions: functions);
    final code = (await owner.createInvite()).code;

    // A second FirebaseApp gives a genuine second emulator Auth UID,
    // separate Firestore cache and distinct access permissions.
    final secondApp = await Firebase.initializeApp(
      name: 'caregiver-$nonce',
      options: primaryApp.options,
    );
    try {
      final bAuth = FirebaseAuth.instanceFor(app: secondApp);
      final bDb = FirebaseFirestore.instanceFor(app: secondApp);
      final bFunctions = FirebaseFunctions.instanceFor(
        app: secondApp,
        region: 'europe-west1',
      );
      await bAuth.useAuthEmulator(host, 9099);
      bDb.useFirestoreEmulator(host, 8080);
      bFunctions.useFunctionsEmulator(host, 5001);
      final caregiverEmail = 'caregiver-$nonce@example.test';
      await bAuth.createUserWithEmailAndPassword(
        email: caregiverEmail,
        password: 'test-password-123',
      );
      await verifyEmulatedEmail(bAuth, caregiverEmail, host);
      final bUid = bAuth.currentUser!.uid;
      expect(bUid, isNot(uid));
      await bFunctions.httpsCallable('redeemInvite').call<Map<String, dynamic>>(
        {'code': code},
      );
      final bOps = bDb.collection(path);
      final base = await bOps
          .doc(startId)
          .get(const GetOptions(source: Source.server));
      expect(base.exists, isTrue);

      final start = (base.data()!['startedAtUtc'] as Timestamp)
          .toDate()
          .toUtc();
      final now = DateTime.now().toUtc();
      final end = now.isAfter(start)
          ? now
          : start.add(const Duration(seconds: 1));
      final stopId = 'stop-$nonce';
      await bOps.doc(stopId).set({
        'schemaVersion': 1,
        'actorId': bUid,
        'sessionId': base.data()!['sessionId'],
        'parentIds': [startId],
        'deleted': false,
        'recordedAtUtc': Timestamp.fromDate(DateTime.now().toUtc()),
        'startedAtUtc': Timestamp.fromDate(start),
        'endedAtUtc': Timestamp.fromDate(end),
      });
      await until(find.text('Start sleep'), 'A sees B stop sleep');
      final finalDocs = await operations.get(
        const GetOptions(source: Source.server),
      );
      expect(finalDocs.docs.map((d) => d.id).toSet(), {startId, stopId});

      await owner.revokeCaregiver(bUid);
      await expectLater(
        bOps.doc(stopId).get(const GetOptions(source: Source.server)),
        throwsA(anything),
      );
    } finally {
      await secondApp.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
