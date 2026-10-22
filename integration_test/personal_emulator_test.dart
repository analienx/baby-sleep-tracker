import 'package:baby_sleep_tracker/app/personal_bootstrap.dart';
import 'package:baby_sleep_tracker/features/personal/data/personal_cloud_client.dart';
import 'package:baby_sleep_tracker/features/personal/presentation/personal_gate.dart';
import 'package:baby_sleep_tracker/features/sleep/data/firestore_sleep_repository.dart';
import 'package:baby_sleep_tracker/features/sleep/domain/sleep_session.dart';
import 'package:baby_sleep_tracker/main.dart' as application;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Real Flutter Android app + Auth/Firestore emulator, synthetic identities.
/// This is not a live Spark project or a substitute for physical-device QA.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'private journal survives offline reattach and denies other UIDs',
    (tester) async {
      expect(usePersonalEmulator, isTrue);
      expect(usePersonalStaging, isFalse);

      Future<void> until(Finder finder, String purpose) async {
        final deadline = DateTime.now().add(const Duration(seconds: 65));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 250));
          if (finder.evaluate().isNotEmpty) return;
        }
        final visible = tester
            .widgetList<Text>(find.byType(Text))
            .map(
              (widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '',
            )
            .where((value) => value.isNotEmpty)
            .take(25)
            .join(' | ');
        throw TestFailure(
          'Timeout during $purpose. Visible: $visible. '
          'Framework: ${tester.takeException()}',
        );
      }

      await application.main();
      await until(find.text('Start sleep'), 'personal account ready');
      expect(find.text('PRIVATE DEV'), findsOneWidget);

      final app = Firebase.app();
      final auth = FirebaseAuth.instanceFor(app: app);
      final firestore = FirebaseFirestore.instanceFor(app: app);
      final uid = auth.currentUser!.uid;
      expect(auth.currentUser!.isAnonymous, isTrue);
      final ops = firestore
          .collection('personalSleep')
          .doc(uid)
          .collection('operations');

      await firestore.disableNetwork();
      await tester.tap(find.text('Start sleep').first);
      await until(find.text('Wake up'), 'offline start visible');
      final cache = await ops.get(const GetOptions(source: Source.cache));
      expect(cache.docs.length, 1);
      expect(cache.docs.single.metadata.hasPendingWrites, isTrue);
      final firstId = cache.docs.single.id;

      // Reattach a fresh widget/repository while the network is still off.
      // OS process-kill persistence is a separate physical acceptance gate.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Reattaching journal'))),
      );
      final personalClient = PersonalCloudClient(
        auth: auth,
        firestore: firestore,
      );
      await tester.pumpWidget(PersonalGate(client: personalClient));
      await until(find.text('Wake up'), 'cached journal reattached');

      // Erasure must remove the journal workspace, not merely disable one
      // button. No private history or write controls may remain visible.
      personalClient.deletionInProgress.value = true;
      await tester.pump();
      expect(find.text('Deleting private cloud records…'), findsOneWidget);
      expect(find.text('Wake up'), findsNothing);
      final blockedRepo = FirestoreSleepRepository.personal(
        firestore: firestore,
        uid: uid,
        writeBlocked: personalClient.deletionInProgress,
      );
      try {
        await blockedRepo.readSessions();
        await expectLater(
          blockedRepo.put(
            SleepSession(
              id: 'write-during-deletion',
              startedAtUtc: DateTime.utc(2026, 10, 20),
              endedAtUtc: null,
            ),
          ),
          throwsA(isA<StateError>()),
        );
      } finally {
        await blockedRepo.dispose();
      }
      personalClient.deletionInProgress.value = false;
      await tester.pump();
      await until(
        find.text('Wake up'),
        'workspace restored after cancellation',
      );

      await firestore.enableNetwork();
      await firestore.waitForPendingWrites().timeout(
        const Duration(seconds: 65),
        onTimeout: () => throw TestFailure('Offline operation never synced'),
      );
      final synced = await ops.get(const GetOptions(source: Source.server));
      expect(synced.docs.length, 1);
      expect(synced.docs.single.id, firstId);
      expect(synced.docs.single.metadata.hasPendingWrites, isFalse);

      await tester.tap(find.text('Wake up').first);
      await until(find.text('Start sleep'), 'ended sleep visible');
      await firestore.waitForPendingWrites();
      final finished = await ops.get(const GetOptions(source: Source.server));
      expect(finished.docs.length, 2);
      expect(finished.docs.map((doc) => doc.id).toSet().length, 2);

      const host = String.fromEnvironment(
        'FIREBASE_EMULATOR_HOST',
        defaultValue: '10.0.2.2',
      );
      final second = await Firebase.initializeApp(
        name: 'stranger-${DateTime.now().microsecondsSinceEpoch}',
        options: app.options,
      );
      try {
        final strangerAuth = FirebaseAuth.instanceFor(app: second);
        final strangerDb = FirebaseFirestore.instanceFor(app: second);
        await strangerAuth.useAuthEmulator(host, 9099);
        strangerDb.useFirestoreEmulator(host, 8080);
        await strangerAuth.signInAnonymously();
        expect(strangerAuth.currentUser!.uid, isNot(uid));
        await expectLater(
          strangerDb
              .collection('personalSleep')
              .doc(uid)
              .collection('operations')
              .get(const GetOptions(source: Source.server)),
          throwsA(anything),
        );

        // Keep both Firebase apps alive until the original user completes
        // deletion. Earlier secondary-app teardown may interfere with the
        // Android Firestore plugin's pending-write check.
        // This still cannot prove production erasure with another device.
        // Renamed Baby 1 + an extra baby: erasure must drain the nested
        // journal and remove both profiles without ever listing the
        // Rules-denied babies/primary/operations collection. Before the
        // fix, that list query aborted deletion for renamed owners.
        final root = firestore.collection('personalSleep').doc(uid);
        await root.collection('babies').doc('primary').set({
          'name': 'First',
          'createdAt': FieldValue.serverTimestamp(),
        });
        await root.collection('babies').doc('child-test').set({
          'name': 'Second',
          'createdAt': FieldValue.serverTimestamp(),
        });
        final at = Timestamp.fromDate(DateTime.utc(2026, 10, 22, 9));
        await root
            .collection('babies')
            .doc('child-test')
            .collection('operations')
            .doc('child-nap')
            .set({
              'schemaVersion': 1,
              'actorId': uid,
              'sessionId': 'sleep-child',
              'parentIds': <String>[],
              'deleted': false,
              'recordedAtUtc': at,
              'startedAtUtc': at,
              'endedAtUtc': Timestamp.fromDate(
                DateTime.utc(2026, 10, 22, 9, 30),
              ),
            });
        final deleting = personalClient.deleteAccount();
        await tester.pump();
        expect(find.text('Deleting private cloud records…'), findsOneWidget);
        await deleting.timeout(const Duration(seconds: 65));
        await tester.pump();
        expect(auth.currentUser, isNull);
        expect(personalClient.deletionNotice.value, contains('deleted'));
      } finally {
        await second.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
