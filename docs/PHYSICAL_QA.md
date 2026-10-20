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
