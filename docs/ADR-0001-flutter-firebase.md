# ADR-0001 — Flutter + Firebase for a family-first sleep tracker

**Status:** Accepted as the initial implementation baseline  
**Date:** 2026-10-19  
**Owner:** Baby Sleep Tracker  
**Supersedes:** None

## Context

This repository was empty when planning began. The app must run natively on Android and iPhone, be beautiful at night, work when offline, be usable one-handed, and share a trustworthy timeline between two independent caregiver accounts. We want the smallest sustainable architecture that can later expand without building a generic baby care platform now.

## Decision

Build one Flutter/Dart app, separated into presentation, domain/repository and infrastructure boundaries. Use Firebase Authentication, Cloud Firestore's native mobile offline persistence and realtime subscriptions, household-scoped Firestore Security Rules, and a narrowly scoped trusted invite/revoke function. Use Riverpod and go_router, with core date/time arithmetic in pure Dart. Use GitHub Actions CI, Firestore emulators and real Android/iOS device gates.

Firestore is canonical for synced household state; its on-device persistent cache supports offline local reads and queued writes. Do **not** add SQLite, a REST server, a second sync engine, an always-on timer background service, or a generic event-stream platform to v1.

Track mutating actions with stable IDs and an immutable audit/action record alongside session state, specifically to detect conflicting offline edits. Never rely on Firestore last-write-wins for domain conflict correctness. Cross-device offline starts cannot guarantee a globally unique active sleep; the user must be able to resolve a conflict on reconnection.

## Considered alternatives

| Option | Benefit | Why not selected |
| --- | --- | --- |
| Native Swift + Kotlin | Deepest OS integration | Duplicated small-app development and parity burden |
| React Native/Expo | Strong cross-platform alternative, TypeScript | Flutter preferred for visual consistency and custom design; reconsider if team expertise changes |
| PWA | Lowest deployment friction | Native ergonomics, store distribution, OS integration and background behavior constraints |
| Custom Postgres + REST | Data portability and SQL | Auth, offline queues, reconciliation and realtime require custom infrastructure |
| Independent SQLite + cloud replication | Maximum control over local source-of-truth | Two data stores and conflict synchronization engine create avoidable MVP complexity |
| Local-only app | Privacy and simplicity | Does not meet the two-caregiver synchronization requirement |

## Consequences

Positive:
- UI parity, one shared time calculation engine and high-fidelity light/dark design.
- Fast local writes, offline session state, realtime sync without bespoke backend.
- Clear permission rules and emulator-driven security testing.
- Low-operational-footprint backend for a single family.

Costs/risks:
- Vendor dependence and future migration work; mitigate with repository boundary, schema versions and JSON export.
- Firestore offline writes are eventually consistent and same-document collisions use last-write-wins. Additional domain action logs, conflict detection and tests are mandatory.
- Offline writes are not recoverable after device data wipe/uninstall before synchronization.
- Cloud location choice requires deliberate provisioning; Auth/data processing geography must be evaluated separately.
- Revoking a caregiver immediately blocks authorized server access but cannot guarantee deletion of previously cached records on an offline device.
- Some widgets/Live Activities require Swift/Kotlin extensions, deferred outside v1.

## Hard invariants

1. No session depends on background timer execution; elapsed time is `now - saved instant`.
2. Every local user action is idempotently identified.
3. No silent loss of competing caregiver modifications.
4. UTC instants at rest; timezone only for views and daily aggregation.
5. Every cloud request is denied unless authenticated household membership authorizes the exact resource.
6. No real child data in source or CI artifacts.
7. Offline/sync/conflict statuses truthfully distinguish local and remote completion.
8. No medical inferences from sleep logs.

## Trigger to revisit ADR

Revisit only if real acceptance testing shows the native Firestore cache cannot meet offline/session consistency requirements, the team needs unsupported hardware/platform integrations, a third-party interoperability requirement becomes a first-class feature, or scaling/privacy requirements demonstrably justify a custom sync backend. Document evidence and migration cost before changing.

## References

- [Full implementation plan](IMPLEMENTATION_PLAN.md)
- [Flutter platform integration](https://docs.flutter.dev/platform-integration)
- [Flutter offline-first patterns](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- [Cloud Firestore offline persistence](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
- [Cloud Firestore transaction offline limitation](https://firebase.google.com/docs/firestore/manage-data/transactions)
- [Firebase Security Rules testing](https://firebase.google.com/docs/firestore/security/test-rules-emulator)
