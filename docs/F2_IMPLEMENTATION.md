# F2 — family sharing, security and synchronization (draft)

Branch: `feat/f2-family-sharing` (stacked on F1 History, PR #24). G0 and G1 are open; **do not merge** or deploy.

## Modes and safe defaults
- Default: volatile demo, visibly not saved.
- `--dart-define=USE_FIREBASE_EMULATOR=true`: legacy F1 synthetic anonymous sandbox; start with `firebase emulators:start --config firebase.dev.json --project demo-little-rest`.
- `--dart-define=USE_FAMILY_EMULATOR=true`: F2 Auth + Firestore + Functions, run `firebase emulators:start --config firebase.json --project demo-little-rest`. Android emulator connects through 10.0.2.2; iPhone simulator localhost.
- `--dart-define=USE_FAMILY_PRODUCTION=true --dart-define-from-file=private/family-prod.json`: explicit real Firebase opt-in. Never enable until independent G2 security review, project provisioning, App Check, deletion policy, and deployment checklist. Real Firebase IDs are client configuration, not privileged secrets. **Never commit service account keys**.
- All F2 Functions run in `europe-west1`; choose an EU Firestore database location before provisioning. Firebase Auth metadata may follow different geographic processing rules.

## Auth and identity
Anonymous sign-in on first online start, persistent on the installed device. `linkWithCredential` email/password preserves the existing UID, sleep data and family membership. A credential already in use is rejected with a visible error; **never automatically sign in and orphan an anonymous family**. An existing account may sign into a fresh unjoined install; unsigned offline drafts cannot be carried between identities. Email/password is supported on Android and iOS. Password reset/recovery UX and external identity providers remain follow-up work, not a claimed G2 pass.

## Access control
- `users/{uid}` stores server-verified family and baby pointer; only that UID can read it.
- `families/{id}/members/{uid}` roles are server-written only. A current member can view family/baby/member data.
- `families/{id}/babies/{babyId}/operations/{opId}` immutable create-only audit DAG; author must match authenticated UID; query listeners carry cache/pending/synced metadata.
- `familyInvites/{sha256(code)}` server only, random 256-bit code, expires after 24h, single transactionally redeemed use, issuer must still be a member.
- Owner can revoke a non-owner; self/owner removal prohibited in v1. Revocation forbids further cloud access once a client reconnects; already cached offline records cannot be remotely erased.
- Cloud Functions Admin SDK writes may bypass Rules; their guards and transactions are part of the security perimeter. Enforce App Check and configure rate limits before public release.

## Conflict and offline semantics
The F1 DAG preserves concurrent parent edits as distinct immutable operations. Repeated commands create UUID document IDs and future retries reuse the same ID. Client acknowledges local snapshot independently of cloud receipt; `pending`, `cached`, `synced`, and `failed` are never conflated. F1 conflict UI lets parents inspect head revisions and write an explicit multi-parent reconciliation operation. Overlapping distinct sleep sessions remain visible rather than deleted; total calculations use interval union.

## Evidence, limitations, blockers
- Required CI: Flutter formatting/analyzer/tests and Android/iOS simulator builds, Functions syntax/unit tests, Rules emulator adversarial tests, Auth+Functions integration tests.
- G2 requires physical iPhone and Android with two distinct accounts: offline writes, concurrent stops in both reconnect orders, kill/restart, permission rejection after revoke, restore on second phone, and end-to-end invitation flow.
- Limits to review: cached data visibility on a shared physical device after signing out, auth credential collision recovery, Cloud Functions outage feedback, server-side rate limiting and Firestore operation-journal query size. Do not distribute to other families until resolved or explicitly mitigated.
- Environment-specific Firebase configuration and production rules deployment are **not done** in this branch.

## F2 review remediation (19 October 2026)
The current PR #25 now incorporates remediation for the three P1 review findings:
- Firestore parent IDs are bounded, nonempty strings and cannot self-reference. As Firestore Rules have no generic `List<String>` type, each accepted position is checked explicitly. We **do not** require every parent document to exist at the time of the write, because legitimate offline replay can contain pending ancestors. A malformed/partial cached graph is quarantined **by session**, without removing its immutable operations or hiding unrelated valid sessions.
- The Firestore client isolates malformed documents, exposes an explicit failed/degraded storage status, and retains the last valid history through failed writes. The error state is no longer permanent: healthy snapshots clear listener failure, successful later writes clear prior write failure, and terminal listener errors trigger a bounded resubscription attempt. This is not a claim of infinite retry or guaranteed persistence while disconnected.
- UI badges and storage descriptions distinguish volatile preview, F1 synthetic emulator, F2 family emulator and F2 cloud. F2 never claims `PREVIEW/not saved` merely because the legacy F1 flag is off. Cache, pending writes, synced and failed states remain distinct.
- Family pointer snapshots preserve Firestore `isFromCache` metadata; offline cached membership is labeled *unverified*, and an unverified cached absence cannot initiate new family creation. A revoked member may still have locally cached historic records while offline.

Evidence includes a standalone Dart reproduction of quarantine/recovery, domain regression tests, and adversarial Firestore Rules tests for every allowed parent-index bound (plus invalid scalar/empty/self-referential parent IDs). These checks do **not** close G2: full two-phone offline/edit/reconnect and physical UI accessibility remains outstanding.
