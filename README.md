# Baby Sleep Tracker

A calm, family-first sleep tracker for Android and iPhone.

**Status:** Product architecture and delivery planning. No application code has been implemented yet.

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

Each phase has a blocking GitHub review gate. The next phase may be developed incrementally, but no phase is considered accepted until its gate's test evidence and checklist are complete.

## Public repository notice

Never commit real child data, authentication secrets, Firebase service account credentials, signing keys, exports, or device-specific personal information. This repository's open-source license has not yet been selected.
