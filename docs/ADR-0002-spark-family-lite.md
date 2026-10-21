# ADR — Spark Family Lite without Cloud Functions

**Status:** Proposed, **not deployed**. Owner approval and emulator security gate required.  
**Date:** 2026-10-21  
**Target:** Two separately authenticated parents sharing one Little Rest sleep journal on Firebase's **no-billing Spark plan**.

## Finding

The existing F2 family implementation assumes Firebase callable Cloud Functions for create/invite/redeem/revoke/delete; Cloud Functions cannot be deployed to a Spark project. This is a choice of implementation, **not** a Firebase restriction on multiple people using Cloud Firestore. Firestore Rules can authorize cross-account access by checking owner-managed membership documents.

**Do not change the deployed `firestore.rules` or claim live family functionality merely because this ADR exists.** First run adversarial Rules tests and both-parent emulator tests, then the physical cross-device QA gate.

## Proposed low-risk design: verified-owner UID grant

Keep the existing immutable operation collection under a single *owner* namespace:

- `personalSleep/{ownerUid}/operations/{opId}`: the **same** immutable sleep DAG already used by Spark personal accounts.
- `personalSleep/{ownerUid}/caregivers/{caregiverUid}`: *owner-written* authorization documents, exact bounded schema: `{role:"caregiver", createdAt:serverTimestamp()}`.
- `personalSleep/{ownerUid}/control/state`: optional owner-only control including `deleting` fence; all Rules checks consult it before allowing either participant to read/write cloud operations.
- An invited caregiver stores `ownerUid` as their active journal pointer **locally** after an online membership verification. They do not receive the owner's password, ID token or account.
- `FirestoreSleepRepository.personal` must separate **journal owner UID** (path) from **signed-in actor UID** (operation.actorId). The existing operation validator already enforces actorId == request.auth.uid; keep that invariant.
- Only one family/journal active per installation in v1; no automatic copying or merging independently written journals.

### Pairing UX

1. Parent B creates/recovers a **distinct verified email/password Firebase Auth identity** and taps *My caregiver ID*. Display the Firebase UID as a QR and Copy/Share action, with a short confirmation fingerprint. A UID is an identifier, **not a secret**.
2. Owner A scans/pastes that UID, verifies the fingerprint in person or via a trusted out-of-band call, then approves *Add caregiver* while online.
3. A **alone** creates the caregiver grant. Parent B enters the owner's UID or scans the owner's pairing QR, checks that the server grant exists, and explicitly chooses **Join this journal**. The gate rebinds the repository to `ownerUid` without changing their Firebase Auth UID.
4. Owner A can revoke B by deleting the grant; server authorization of B's subsequent reads/writes stops immediately after revocation. B's offline cache may still display old records; the UI must identify it as unverified and prevent claims of confirmed membership.

This pairing is **not** a secret-code bearer invitation. An attacker who knows a UID still cannot grant themselves membership. Avoid 6-digit login tokens, broadly readable invites, self-writable membership, or permissive `allow write: if signedIn()` shortcuts.

### Example *conceptual* Rules contract, not deployment-ready source

```
// Every access requires a signed-in identity.
canReadOrWrite(ownerUid) =
  request.auth.uid == ownerUid ||
  (request.auth.token.email_verified == true &&
   exists(/databases/{database}/documents/personalSleep/{ownerUid}/caregivers/{request.auth.uid}));

// Rule on /caregivers/{caregiverUid}:
//   create: owner UID only; exact role/fields; no self-grant.
//   delete: owner UID only.
//   update: forbidden (delete + create explicit).
//   get: owner or matching caregiver.
//   list: owner only.
//
// Rule on /operations/{opId}:
//   get/list: owner or verified, nonrevoked caregiver, unless deleting.
//   create: same authorization + validOperation(opId), which requires
//           operation.actorId == request.auth.uid.
//   update: forbidden.
//   delete: owner-only, and only within a fenced, online deletion process.
```

Actual deployed Rules must use valid fully-qualified Firestore paths, bounded data, token checks, and safe `get()`/ `exists()` evaluation; this sketch is intentionally non-executable. No cloud authorization decision may depend solely on local SharedPreferences.

## Critical limitations (not equivalent to trusted backend)

- **Account/household erasure** needs a rules-enforced, durable owner-owned deletion fence before any recursive client deletion. Without a server, the owner must remain online to enumerate/delete nested documents; other devices may retain cached exports or records. Auth deletion must not proceed while member access or pending writes can recreate operations. Gate this as a separate threat-model review, and fail closed rather than promising irreversible global deletion.
- Firestore Rules do not run scheduled cleanup, server-issued quotas, per-IP abuse limits, secret hashing or Firebase Auth Admin SDK deletion. Limit the number of caregivers in the UI, watch Spark usage, and retain stronger F2 Functions as an optional future production track.
- Owner must not authorize an arbitrary UID without explicit confirmation. Membership grants don't identify a human by themselves.
- Spark quotas include 50,000 reads and 20,000 writes/day (including Rules document reads); abuse can exhaust the free project, stopping services for the billing period. App Check is available on Spark but does **not** replace Rules.
- Auth tokens may need refresh after email verification. A revoked device that is offline may still show locally cached data; any queued writes must be rejected at the server when reconnecting.
- Keep the existing solo journal working; do not migrate, merge or clear data silently. Use synthetic-only QA until G2/G3 signoff.

## Required automated acceptance before connecting a real Spark project

1. Two distinct UIDs join the same journal, share a single operation sequence, preserve distinct actor IDs, and observe edits on both devices.
2. Anonymous/unverified strangers and guessed UIDs cannot read/write; caregivers cannot create/update/delete any membership grants; self-grant and role escalation fail.
3. A revoked caregiver's server reads and writes fail; offline queued operations are rejected on reconnect; owner remains able to read and operate.
4. The owner cannot delete/revoke another owner's family; no normal caregiver can delete journal records, change ACLs or access a different family.
5. Deletion fencing prevents **new writes from any device** before owner deletion proceeds. Retry after partial erasure must not restore access. Delete-account must not wrongly wipe another parent's shared data.
6. Sign-out, sign-in, process restart, reconnect, account linking, two-parent conflict DAG and large-text/accessible pairing UI.
7. Firestore Rules and Flutter integration tests must run on GitHub runners; no local Java required. Physical Android + iOS and independent G2/G3 review remain release gates.

## Rollout options

**Today, zero-code workaround:** Both phones sign into the *same* recoverable Firebase Auth account. This shares the same journal because the application keys by UID, but provides no individual identities, independent revocation, or per-person attribution. Only synthetic QA data; protect the account with email/password first. A fresh phone's anonymous identity must have zero data before switching.

**Preferred implementation:** Owner-approved UID grant, separate Firebase accounts, the same append-only journal, and an isolated `USE_SPARK_FAMILY_LITE` rollout gate. It needs real code/rules/security tests but **does not require Blaze**.

**Later option:** Keep the current F2 Cloud Functions backend for stronger server-issued invitation codes, Admin SDK account deletion, quotas and trusted cleanup if billing is explicitly approved.

## Primary Firebase references

- https://firebase.google.com/docs/projects/billing/firebase-pricing-plans
- https://firebase.google.com/docs/firestore/security/rules-conditions
- https://firebase.google.com/docs/firestore/manage-data/transactions
- https://firebase.google.com/docs/firestore/security/rules-query
- https://firebase.google.com/docs/auth/limits
