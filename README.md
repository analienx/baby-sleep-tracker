# Baby Sleep Tracker

A calm, family-first sleep tracker for Android and iPhone.

**Status:** F0 implementation preview. The native Flutter Android/iOS shell is
implemented, but records are **not persisted** and no Firebase project has been
configured. Do not use this build to log real sleep or rely on it for records.

## Run the F0 prototype

Prerequisites: Flutter **3.47.7** (stable), Dart **3.13.5** (bundled), Android
Studio/Android SDK for Android, or macOS/Xcode for iOS. Run from the repository
root:

```sh
flutter pub get --enforce-lockfile
flutter run
```

The app opens on Today. Tap **Start sleep** / **Wake up** to interact with a
memory-only demonstration, or navigate between **Today**, **History** and
**Trends**. Every screen marks its preview status: all entries disappear when
the app restarts. No child profile, credentials, synthetic sleep fixture or
Firebase network call is configured in the running app.

### Development checks

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Unit tests inject a fake clock and synthetic sessions. The two golden snapshots
under `test/goldens/` capture the light/dark Today visual baseline. Updating
them requires an intentional review (`flutter test --update-goldens`). CI pins
Flutter and the GitHub Actions source revisions, uses the committed
`pubspec.lock`, scans for secrets and uploads a **debug** Android APK only.

Project layout:

```text
lib/app/                         Navigation, themes, clock and DI
lib/features/sleep/domain/       UTC sessions, calculations, actions, contracts
lib/features/sleep/data/         F0 memory-only preview repository
lib/features/sleep/presentation/ Today, History, Trends
test/domain/                     Deterministic fake-clock/time tests
test/widget_test.dart            Navigation, semantics and visual tests
```

## Product promise

Record a baby's sleep in one tap, review the day at a glance, correct missed events, and share an accurate timeline across caregivers—even when a phone temporarily has no connection.

## First release (v1)

- One-tap sleep start and wake; elapsed sleep and awake time
- Manual entry, editing, undo, and deletion of sleep sessions
- Timeline, rolling 24-hour sleep total, session count, and wake-window duration
- Shared household with caregiver invitation and access controls
- Persistent offline recording and reconciliation after reconnect
- Polished light and dark themes on Android and iPhone
- Private data handling, export, and deletion controls

No feeding, diaper tracking, medical sleep scoring, AI predictions, or passive monitoring in v1.

## Architecture

- **App:** Flutter/Dart, Riverpod, go_router
- **Backend:** Firebase Authentication, Cloud Firestore, narrowly scoped serverless invitation/revocation handlers
- **Persistence:** Firestore native offline persistence; no duplicate custom SQLite sync engine in v1
- **Security:** Household-scoped Firestore Security Rules, emulator rule tests
- **Quality:** GitHub Actions and real-device Android/iOS release gates

Design decisions, data contracts, risks, and review requirements are documented in:
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Architecture decision](docs/ADR-0001-flutter-firebase.md)
- [GitHub backlog](../../issues)

## Development principles

1. A sleep event must survive app termination, a reboot, or loss of connectivity after its local write is committed.
2. A running timer is derived from persisted timestamps, never from a long-running background loop.
3. Two caregivers must not silently overwrite one another's recorded actions.
4. One primary action dominates the home screen; corrections are always easy.
5. All child records are private by default, and every backend path enforces household membership.
6. Do not claim medical accuracy or infer why an infant is awake from sleep-only data.

## Release governance

Each phase has a blocking GitHub review gate. F0 is tracked in issues
[#2](../../issues/2) and [#3](../../issues/3), and blocking review gate
[#4](../../issues/4). No phase is accepted until test evidence and its review
checklist are complete. See [F0 review notes](docs/F0_REVIEW.md).

## Public repository notice

Never commit real child data, authentication secrets, Firebase service account credentials, signing keys, exports, or device-specific personal information. This repository's open-source license has not yet been selected.
