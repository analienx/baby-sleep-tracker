# Real-device Little Rest acceptance runbook

Only synthetic identities and records: demo-little-rest project, never any
production Firebase identifier or actual child data.

## Network setup
The normal emulator configs bind to 127.0.0.1. For a short QA session only,
firebase.device.json explicitly binds Auth/Firestore/Functions to 0.0.0.0.
Use a dedicated trusted LAN, with Windows Firewall restricted to the *specific*
two test phones' private IPs (TCP 9099, 8080, 5001). Never port-forward,
expose on public Wi-Fi, or run it as a background service.

Install Java, Node and Firebase CLI; npm ci in functions/ first. Start:
  firebase emulators:start --project demo-little-rest --config firebase.device.json

On Android and iPhone, create a debug build with:
  --dart-define=USE_FAMILY_EMULATOR=true
  --dart-define=FIREBASE_EMULATOR_HOST=192.168.x.y
where 192.168.x.y is the trusted LAN IP of the computer running Firebase.
For F1 single-device tests use USE_FIREBASE_EMULATOR=true instead.
Android Emulator default is 10.0.2.2; iOS Simulator default is localhost.
Physical iPhone must be built and signed using Xcode/macOS. Do not use
localhost on a physical phone. Never enable emulator flags in release builds.

## Capture the acceptance evidence
1. Record app Git SHA, both physical model/OS versions, host IP, local zone,
   test time and two distinct synthetic Firebase UIDs.
2. A: create family and link email, issue invite. B: protect account, redeem
   invite. Both display identical family and baby IDs.
3. A start -> B observes same session ID; B stop -> A receives exact same end.
   Capture pending/cached/synced state transitions.
4. Disconnect A: Start/Edit/Stop, kill app, relaunch offline and reboot;
   check locally committed session after each. Reconnect and verify server
   revision IDs. An unsynced operation on a lost phone cannot be restored.
5. Disconnect both: edit same previously synced record independently; connect
   A then B. Verify both immutable revisions, unresolved heads and explicit
   reconciliation, then reverse network order in a separate scenario.
6. Test overlap arithmetic, DST fold/gap selection, undo safety, expired and
   replayed invite denial, forged actor denial and revoked access after B
   reconnects. Offline previously cached data may still be visible.
7. Restore B's recoverable identity on a fresh second install and confirm
   server-acknowledged history returns.
8. With TalkBack and VoiceOver enabled, test Start/Stop, History pickers,
   focus ordering, minimum touch targets, 200% fonts and clear status speech.
   Retain redacted screen recordings and document defects in G0/G1/G2.

## Teardown
Stop Firebase emulators, remove the temporary Windows Firewall allow rule,
discard synthetic invite codes and remove local screenshots containing test
emails. Never accept simulator-only smoke as physical-device gate evidence.

## Repeatable CI E2E (persistent Flutter/Firebase app)

The normal `Flutter CI` installs a **PREVIEW** APK. That launch is useful for
layout checks, but does not verify persistent family tracking.

The separate [Persistent family E2E](/.github/workflows/family-e2e.yml)
workflow does all of the following on a real Android OS emulator:
1. Compiles and archives a **debug APK** using
   `--dart-define=USE_FAMILY_EMULATOR=true`, with an explicit private
   `FIREBASE_EMULATOR_HOST` for the downloadable artifact.
2. Boots Android, starts **real** synthetic Auth, Firestore and Cloud Functions
   emulators, installs the archived APK, verifies launch and takes a screenshot
   of the family onboarding UI.
3. Runs `integration_test/family_emulator_test.dart` through Flutter's
   on-device test driver. It creates a family through the UI, saves an offline
   Start action into native Firestore cache, recreates the UI/repository
   offline, reconnects and verifies the **same** operation ID reached the
   emulator backend exactly once. A second Firebase Auth UID joins by invite,
   stops the same sleep in a separate Firestore client, and is then revoked.
4. Archives the integration log and test screenshots. Failing checks fail the
   GitHub workflow; backend emulator startup alone is **not** reported as E2E.

This is genuine app + backend integration. Recreating the Flutter widget tree
is not proof of survival across an Android OS force-stop/reboot, and the
second test identity is **not** a separate physical phone. Both of those are
explicitly left to the physical gate tests above.

The workflow runs when the PR modifies relevant code, or can be triggered
manually after merging the workflow to the repository's default branch. Open
the latest run's Artifacts to retrieve
`little-rest-family-persistent-debug-<sha>` and the evidence archive. The
default debug APK is configured for the **Android emulator's** 10.0.2.2
alias. For testing on a real Android handset, provide that handset's trusted
LAN Firebase host IP using the workflow-dispatch `device_host` input; the
workflow validates RFC1918/loopback IPv4. Otherwise build locally with:

```sh
flutter build apk --debug --dart-define=USE_FAMILY_EMULATOR=true \
  --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10
```

The debug APK is **not** a standalone online service. A phone on the LAN must
reach the separately running emulator host and use demo-little-rest only. No
release APK can connect to the emulator by design. Real family use requires
independent G2 approval and a provisioned production Firebase configuration.
