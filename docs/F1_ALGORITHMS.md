# F1 algorithm decisions and verification status

**Date:** 2026-10-19
**Status:** In progress. Stacked on the unapproved F0 draft; G0 #4 remains a
blocking human review gate. This document is not G1 #9 sign-off.

## 1. Time and local calendars — #5, #8

Use real UTC instants and half-open `[start,end)` intervals. A finished record
must end strictly after it starts, and a single record longer than 24 hours is
rejected with an actionable error. Active records have `end=null` and are
clipped at the injected `nowUtc` instant for reports.

Sort clipped intervals by start and merge overlapping/touching ranges in
**O(n log n)** time; total the union rather than summing individual sleeps.
The operation also returns original session IDs involved in overlaps so a
human can inspect the unmodified records. The hourly strip intentionally
indicates *which hours contain sleep*, not the percentage slept within each
hour; precise totals come from the union calculation.

Daily totals are computed from those merged UTC instants and split at the
**next civil midnight in an explicit IANA time zone**, never by adding a
24-hour duration to local midnight. Prague spring and autumn days therefore
have 23 and 25 real hours, respectively. Device travel changes the day label
but not elapsed sleep. Golden screenshots and locale/zone device QA remain
required.

## 2. Competing offline edits — #6, F2 #12

Firestore officially supports offline cache/queued writes for mobile, but
the same-document conflict behavior is **last write wins**; mobile transactions
do not work offline. Never treat a mutable session document as the sole
conflict-safe source of truth.

Each action is one append-only document with a UUID ID, a complete validated
snapshot, actor, UTC recorded instant, and parent revision IDs. A retried
action must reuse exactly the same ID and payload. Revision ancestry, **not
device wall-clock timestamp**, determines causality. The reducer:

1. Validates unique IDs, parent references, and cycles.
2. Reconstructs a deterministic revision DAG regardless of arrival order.
3. When exactly one head exists, uses that session snapshot (or tombstone).
4. When multiple heads exist, preserves every competing version and presents
   only their last common, uncontested ancestor as provisional state.
5. Requires an **explicit multi-parent reconciliation operation** to merge
   conflicting heads. Automatic last-write-wins or silent deletion is banned.

Independent session IDs can still create overlapping/multiple active sleeps;
they are reported by the interval layer and **not destructively merged**.
This graph is an application-level safeguard, not a global cross-device lock.

## 3. Local versus remote persistence — #6

The experimental `--dart-define=USE_FIREBASE_EMULATOR=true` mode connects
exclusively to development Auth + Firestore emulators using a synthetic
anonymous user and `demo-little-rest` Firebase project ID. Default builds
remain explicitly volatile preview mode. Production credentials, production
Auth, household permissions, and live deployments do not exist in this PR.

The native Android/Apple Firestore cache is enabled. A `set()` Future may wait
for **remote** acknowledgement while offline, so the repository accepts a
command after observing its immutable operation in the **local Firestore
listener**. This proves visibility to that local cache view, **not** server
sync or storage-hardware durability. Later server rejection is surfaced as an
error. Metadata drives the labels:

| State | Truthful statement |
| --- | --- |
| Preview | Volatile; will be lost at relaunch |
| Opening | Cache has not delivered its first snapshot |
| Cached | Local data available; server freshness not verified (`isFromCache`) |
| Pending | One or more local writes pending backend ack (`hasPendingWrites`) |
| Synced | Listener reports no pending writes and a server-current snapshot |
| Failed | Decode, permissions or persistence issue; no success claim |

`isFromCache` **is not** a reliable internet connectivity detector. A cached
snapshot may represent previously synchronized data; avoid labeling it
"offline" with certainty. The active timer is `nowUtc - saved UTC start`,
without an always-on background service.

## Emulator smoke run (synthetic records only)

1. Install Firebase CLI and run `firebase emulators:start --project demo-little-rest`
   in the repository root. The `firestore.rules` file **must not** be deployed
   to a real project; it is the narrow F1 dev-user-only rule set.
2. Android emulator: `flutter run --dart-define=USE_FIREBASE_EMULATOR=true`
   (`10.0.2.2` maps to host). For the iOS simulator the app uses `localhost`.
3. First launch requires the Auth emulator for synthetic sign-in. After this,
   test start → airplane mode/network disconnect → stop → kill/relaunch →
   restore network → verify `Pending` becomes `Synced`, and the same session ID
   remains. Repeat on real Android/iPhone hardware, adapting the host address;
   the current hardcoded loopback is simulator-only.
4. Simulate two offline edits with the same parent revision ID; inspect that
   both immutable operations exist and a conflict is flagged. Test revocation
   and permission denial after rejoin in F2 security work.

## Still unverified / blockers

- G0 #4 independent real-device and accessibility review; no gate bypass.
- G1 #9 physical-device restart/airplane-mode/fsync and emulator permission
  tests. Local listener visibility is not proof of force-stop/reboot survival.
- History's manual exact-timestamp entry, editing, deletion and explicit
  conflict resolution UI (#7) are not built in this slice.
- The normal release build is **not a functioning persisted tracker**. Never
  enter a real baby's sleep data into preview or demo mode.
- F2 household membership, secure invitations and cross-account reconciliation
  require separate security rules and independent review.

## Authoritative sources

- [Firestore offline persistence and last-write-wins](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
- [Firestore transactions and batched writes; offline transaction limitation](https://firebase.google.com/docs/firestore/manage-data/transactions)
- [Firestore snapshot listener metadata](https://firebase.google.com/docs/firestore/query-data/listen)
- [Connect Firestore emulators](https://firebase.google.com/docs/emulator-suite/connect_firestore)
- [Connect Authentication emulator](https://firebase.google.com/docs/emulator-suite/connect_auth)
- [Dart timezone / IANA database](https://pub.dev/packages/timezone)
