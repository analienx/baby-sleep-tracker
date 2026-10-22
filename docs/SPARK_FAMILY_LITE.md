# Spark Family Lite — secure two-parent sharing, no billing

**Implementation:** [PR #32](https://github.com/analienx/baby-sleep-tracker/pull/32) · **Status:** deployed to *Spark staging only* (Rules + signed Android QA APK), **not production-approved**, synthetic data · **Architecture:** [ADR-0002](ADR-0002-spark-family-lite.md).

This is the **only active family-sharing track**. Existing F2 Cloud Functions remain in the repository for compatibility and as a potential future option, but are not required by Family Lite. The Spark staging Rules were deployed to `little-rest-stage-jh-261020` on 2026-10-22 after adversarial security and Android two-account emulator tests passed. The signed `0.2.0-beta.2+3` QA APK was installed on Vivo Android 16 with existing staging app data preserved. Real two-phone family acceptance and independent security review remain open.

## What the family sees

- Both parents maintain separate Firebase Auth accounts with **verified email addresses**.
- Parent A owns a persistent journal. In **Settings → Family**, A copies their owner ID, and B copies their caregiver ID. They verify each other's identity out of band.
- A enters B's caregiver ID and taps **Approve caregiver**. The Firestore grant is written by **A alone**.
- B enters A's owner ID and taps **Join shared journal**. The app fetches the grant directly **from the server** before selecting A's journal. Local preference cannot grant access.
- Both use the *same* immutable operation history, but each operation records its actual authenticated actor ID; sync and conflict resolution reuse the existing Firestore repository.
- A can **Revoke caregiver**; Firestore Rules deny B's subsequent server reads and writes. Cached records on an offline device cannot be remotely erased; its queued writes fail on reconnect.
- B can switch back to their personal journal locally; no data is merged or erased as a side effect.
- The app fails closed when previously saved membership cannot be verified at cold start; it **does not silently record sleep into the wrong parent's journal**. Connect online or explicitly switch to private mode.

## Privacy and security invariants

1. Only the owner creates and deletes `personalSleep/{ownerUid}/caregivers/{caregiverUid}`; neither the caregiver nor a stranger can self-grant or promote themselves.
2. A caregiver requires a verified Firebase Auth email; anonymous or unverified users have no shared-journal access.
3. Only the owner enumerates grants; a caregiver can get their **own** grant, not others.
4. Reads and writes under `personalSleep/{ownerUid}/operations` require owner identity or an active server-side grant. Every immutable new operation must declare its real `actorId`.
5. Before sharing, an irreversible `sharing/state` marker is created. It disables legacy personal-only deletion of shared journal operations without a server-approved deletion fence.
6. Account erasure in Family Lite first commits an irreversible owner-only `control/state` deletion fence, revokes all grants, verifies erasure, deletes operations, then removes Auth. No offline or stale client can issue an accepted write after the fence.
7. Rules document lookups use free Spark quota; test Firestore reads and snapshots before promoting production load. Security Rules are authoritative, **not client UI state**.
8. Cloud Functions, billing, client-managed secret invitations and public membership lists are not part of this design.

## Opt-in emulator testing

The active compile-time flag is `USE_SPARK_FAMILY_LITE=true`, **only in conjunction with** `USE_PERSONAL_EMULATOR=true` or `USE_PERSONAL_STAGING=true`; the feature is off by default.

GitHub Actions:
- `family-security.yml` executes adversarial Rules tests, including self-grant, unverified UID, impersonation, deletion fencing and legacy erase protection.
- `spark-family-lite-e2e.yml` boots disposable Android / Auth / Firestore emulators and exercises **two separate signed-in Firebase users**, shared operations, server revocation of offline pending edits and the server deletion fence.
- `flutter-ci.yml` checks analysis and unit/widget tests; existing personal and family emulators must not regress.

No local Java is needed. The test-only Spark project now runs the reviewed sharing Rules, and the `feat/spark-family-lite` signed Android workflow builds with the explicit flag. Personal-only APKs from other branches remain separate development outputs; no application-store release exists. Never deploy these experimental Rules to a different Firebase project without its own security gates.

## Current limitations and acceptance still needed

- ID copy/paste pairing is functional but not yet a QR scan workflow. A user must validate the UID against the other parent's screen or trusted phone call; a UID is an identity, not a secret.
- The Flutter owner UI limits itself to one other caregiver. The Rules do not enforce a global count: another authenticated *owner* can add multiple grants from a custom client. Spark free quotas and owner-only access limit impact but a strict server-enforced seat cap is not yet implemented.
- A cold-start offline device with a previously joined family must reconnect to reverify membership before it may write; a running verified session may record offline and show pending writes.
- Firestore alone cannot run TTL cleanup, revoke bytes already cached/exported by an offline phone, or forcibly remove Firebase Auth users belonging to other accounts.
- Independent two-device real Android/iPhone QA, password reset and restore, account deletion under concurrency, App Check enforcement, privacy review and owner release acceptance are **not yet complete**.

For now: **synthetic QA data only.** Previously recorded personal staging sessions remain preserved in the upgraded installation. The original in-memory preview channel stays independent.
