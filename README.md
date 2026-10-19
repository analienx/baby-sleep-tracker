# Baby Sleep Tracker

A calm, family-first sleep tracker for Android and iPhone.

**Status:** F0/F1 remain draft review work; F2 family security is not yet
implemented. F3 experience/export work is stacked on the F1 History draft.
The default app uses **non-persistent preview storage** and no production
Firebase project is configured. Do not use these builds to log real sleep or
rely on them for records.

## Run the preview

Prerequisites: Flutter **3.47.7** (stable), Dart **3.13.5** (bundled), Android
Studio/Android SDK for Android, or macOS/Xcode for iOS. Run from the repository
root:

```sh
flutter pub get --enforce-lockfile
flutter run
```

The app opens on Today. Tap **Start sleep** / **Wake up** to interact with a
memory-only demonstration, or navigate between **Today**, **History** and
**Trends**. Settings (gear icon) provides a device-saved appearance preference
and JSON/CSV sharing of the accepted session snapshot. The seven-day view
uses local civil days, marks absent records as unknown, and labels today as
incomplete. Every screen marks its preview status: all entries disappear when
the app restarts. No child profile, credentials, synthetic sleep fixture or
Firebase network call is configured in the running app.

**F3 limitations:** Export does not include the immutable operation audit
journal or unresolved competing versions. In preview mode, exported records
are not durable. The share sheet may stage temporary files in the app cache;
use a private destination and remove unnecessary copies. Family invitations,
caregiver revocation, account recovery, child/household deletion requests and
cloud-verifiable export are disabled until F2 backend security is implemented
and reviewed. No deletion request is sent from this preview.

### Opt-in offline Firebase development mode (synthetic data only)

In a separate terminal, with Firebase CLI installed:

```sh
firebase emulators:start --project demo-little-rest
```

Then run on an **Android emulator** or **iOS simulator**:

```sh
flutter run --dart-define=USE_FIREBASE_EMULATOR=true
```

The debug app connects to local Auth and Firestore emulators, signs in with a
synthetic anonymous account, and uses the native persistent Firestore cache.
It never falls back silently to preview storage if emulator sign-in fails.
The Today/History banner distinguishes cached, pending and synced states.
This mode is blocked in release builds. Physical phone host routing and
force-stop/reboot behavior are not yet validated. See
[F1 algorithms and smoke checklist](docs/F1_ALGORITHMS.md) for limitations.

### Development checks

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Unit tests inject a fake clock and synthetic sessions. Six golden snapshots
under `test/goldens/` capture light/dark Today, Trends and Settings. Updating
them requires an intentional review (`flutter test --update-goldens`). CI pins
Flutter and the GitHub Actions source revisions, uses the committed
`pubspec.lock`, scans for secrets, uploads a **debug** Android APK and checks an
**unsigned iOS simulator build** on pull requests. No store credentials or
production services are needed.

Project layout:

```text
lib/app/                         Navigation, themes, clock and DI
lib/features/sleep/domain/       UTC sessions, calculations, actions, contracts
lib/features/sleep/data/         Preview and emulator-only Firestore adapters
lib/features/sleep/presentation/ Today, History, Trends
lib/features/settings/           Appearance, export and disabled family controls
lib/l10n/                        English message bundle and localization API
test/domain/                     UTC/DST/operation replay and fake-clock tests
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
[#4](../../issues/4). F1 issues [#5](../../issues/5)–[#8](../../issues/8)
depend on that gate and the F1 review gate is [#9](../../issues/9). No phase is
accepted until test evidence and its review checklist are complete. See
[F0 review notes](docs/F0_REVIEW.md) and
[F1 algorithm evidence](docs/F1_ALGORITHMS.md) and
[F3 review evidence](docs/F3_REVIEW.md).

## Public repository notice

Never commit real child data, authentication secrets, Firebase service account credentials, signing keys, exports, or device-specific personal information. This repository's open-source license has not yet been selected.
