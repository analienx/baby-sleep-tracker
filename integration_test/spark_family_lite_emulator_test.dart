import 'dart:convert';
import 'dart:io';

import 'package:baby_sleep_tracker/app/personal_bootstrap.dart';
import 'package:baby_sleep_tracker/features/personal/data/personal_cloud_client.dart';
import 'package:baby_sleep_tracker/features/personal/data/spark_family_lite_controller.dart';
import 'package:baby_sleep_tracker/features/sleep/data/firestore_sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:baby_sleep_tracker/main.dart' as application;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Two Firebase Auth accounts + two Firestore SDKs in one Android emulator.
/// Strictly synthetic; the backend is the disposable Auth/Firestore emulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Spark owner and verified caregiver sync, revoke offline and fence',
    (tester) async {
      expect(usePersonalEmulator, isTrue);
      expect(useSparkFamilyLite, isTrue);

      Future<void> until(
        Future<bool> Function() predicate,
        String purpose,
      ) async {
        final until = DateTime.now().add(const Duration(seconds: 70));
        while (DateTime.now().isBefore(until)) {
          await tester.pump(const Duration(milliseconds: 240));
          if (await predicate()) return;
        }
        throw TestFailure('Timed out: $purpose');
      }

      Future<void> verifyEmail(FirebaseAuth auth, String email) async {
        final user = auth.currentUser!;
        await user.sendEmailVerification();
        final client = HttpClient();
        try {
          final url = Uri.parse(
            'http://10.0.2.2:9099/emulator/v1/projects/demo-little-rest/oobCodes',
          );
          final response = await (await client.getUrl(url)).close();
          expect(response.statusCode, 200);
          final decoded = jsonDecode(
            await utf8.decoder.bind(response).join(),
          ) as Map<String, dynamic>;
          final codes = (decoded['oobCodes'] as List)
              .cast<Map<String, dynamic>>()
              .where(
                (code) =>
                    code['email'] == email &&
                    code['requestType'] == 'VERIFY_EMAIL',
              )
              .toList();
          expect(codes, isNotEmpty);
          await auth.applyActionCode(codes.last['oobCode'] as String);
          await auth.currentUser!.reload();
          await auth.currentUser!.getIdToken(true);
          expect(auth.currentUser!.emailVerified, isTrue);
        } finally {
          client.close(force: true);
        }
      }

      await application.main();
      await until(
        () async => find.text('Start sleep').evaluate().isNotEmpty,
        'first owner journal',
      );
      final app = Firebase.app();
      final ownerAuth = FirebaseAuth.instanceFor(app: app);
      final ownerDb = FirebaseFirestore.instanceFor(app: app);
      final ownerUid = ownerAuth.currentUser!.uid;
      final ownerPersonal = PersonalCloudClient(
        auth: ownerAuth,
        firestore: ownerDb,
        familyLiteEnabled: true,
      );
      await ownerPersonal.linkEmailPassword(
        'owner-lite@example.test',
        'qa-owner-password-12345',
      );
      await verifyEmail(ownerAuth, 'owner-lite@example.test');
      final ownerLite = SparkFamilyLiteController(
        auth: ownerAuth,
        firestore: ownerDb,
      );
      await ownerLite.initialize();

      final secondary = await Firebase.initializeApp(
        name: 'family-lite-second-parent',
        options: app.options,
      );
      final carerAuth = FirebaseAuth.instanceFor(app: secondary);
      final carerDb = FirebaseFirestore.instanceFor(app: secondary);
      const host = String.fromEnvironment(
        'FIREBASE_EMULATOR_HOST',
        defaultValue: '10.0.2.2',
      );
      await carerAuth.useAuthEmulator(host, 9099);
      carerDb.useFirestoreEmulator(host, 8080);
      await carerAuth.signInAnonymously();
      final carerUid = carerAuth.currentUser!.uid;
      final carerLite = SparkFamilyLiteController(
        auth: carerAuth,
        firestore: carerDb,
      );
      final ownerOps = ownerDb
          .collection('personalSleep')
          .doc(ownerUid)
          .collection('operations');
      final carerOps = carerDb
          .collection('personalSleep')
          .doc(ownerUid)
          .collection('operations');

      try {
        await carerLite.initialize();
        await carerAuth.currentUser!.linkWithCredential(
          EmailAuthProvider.credential(
            email: 'carer-lite@example.test',
            password: 'qa-carer-password-12345',
          ),
        );
        await verifyEmail(carerAuth, 'carer-lite@example.test');
        await expectLater(
          carerOps.get(const GetOptions(source: Source.server)),
          throwsA(isA<FirebaseException>()),
        );
        await ownerLite.approveCaregiver(carerUid);
        await carerLite.joinOwner(ownerUid);
        expect(carerLite.ownerFor(carerUid), ownerUid);

        final ownerRepo = FirestoreSleepRepository.personal(
          firestore: ownerDb,
          uid: ownerUid,
          actorUid: ownerUid,
        );
        final carerRepo = FirestoreSleepRepository.personal(
          firestore: carerDb,
          uid: ownerUid,
          actorUid: carerUid,
        );
        try {
          await ownerRepo.readSessions();
          await carerRepo.readSessions();
          final start = DateTime.now().toUtc().subtract(
            const Duration(hours: 2),
          );
          await ownerRepo.put(
            SleepSession(
              id: 'shared-owner-nap',
              startedAtUtc: start,
              endedAtUtc: start.add(const Duration(minutes: 32)),
            ),
          );
          await ownerDb.waitForPendingWrites();
          await until(
            () async => (await carerRepo.readSessions()).length == 1,
            'caregiver receives owner sleep',
          );
          await carerRepo.put(
            SleepSession(
              id: 'shared-carer-nap',
              startedAtUtc: start.add(const Duration(minutes: 50)),
              endedAtUtc: start.add(const Duration(minutes: 75)),
            ),
          );
          await carerDb.waitForPendingWrites();
          final synced = await ownerOps.get(
            const GetOptions(source: Source.server),
          );
          expect(synced.docs.length, 2);
          expect(synced.docs.map((d) => d.data()['actorId']).toSet(), {
            ownerUid,
            carerUid,
          });

          // A queued write from an offline *revoked* device must fail on
          // reconnect, even if it was optimistically cached first.
          await carerDb.disableNetwork();
          final pending = carerOps.doc('queued-before-revoke').set({
            'schemaVersion': 1,
            'actorId': carerUid,
            'sessionId': 'queued-before-revoke',
            'parentIds': <String>[],
            'deleted': false,
            'recordedAtUtc': Timestamp.fromDate(start),
            'startedAtUtc': Timestamp.fromDate(start),
            'endedAtUtc': Timestamp.fromDate(
              start.add(const Duration(minutes: 10)),
            ),
          });
          final rejection = expectLater(
            pending,
            throwsA(isA<FirebaseException>()),
          );
          await ownerLite.revokeCaregiver(carerUid);
          await carerDb.enableNetwork();
          await rejection.timeout(const Duration(seconds: 65));
          await expectLater(
            carerOps.get(const GetOptions(source: Source.server)),
            throwsA(isA<FirebaseException>()),
          );

          await ownerLite.approveCaregiver(carerUid);
          await carerLite.joinOwner(ownerUid);
          final fence = ownerDb
              .collection('personalSleep')
              .doc(ownerUid)
              .collection('control')
              .doc('state');
          await fence.set({
            'deleting': true,
            'requestedAt': FieldValue.serverTimestamp(),
          });
          await expectLater(
            carerOps.get(const GetOptions(source: Source.server)),
            throwsA(isA<FirebaseException>()),
          );
          await expectLater(
            ownerOps.doc('post-fence').set({
              'schemaVersion': 1,
              'actorId': ownerUid,
              'sessionId': 'post-fence',
              'parentIds': <String>[],
              'deleted': false,
              'recordedAtUtc': Timestamp.fromDate(start),
              'startedAtUtc': Timestamp.fromDate(start),
              'endedAtUtc': null,
            }),
            throwsA(isA<FirebaseException>()),
          );
          await ownerOps.doc(synced.docs.first.id).delete();
        } finally {
          await ownerRepo.dispose();
          await carerRepo.dispose();
        }
      } finally {
        await carerDb.enableNetwork();
        await carerLite.dispose();
        await ownerLite.dispose();
        await secondary.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 9)),
  );
}
