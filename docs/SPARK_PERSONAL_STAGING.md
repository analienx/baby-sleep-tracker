# Firebase Spark daily-use staging — private journal + premium light UI

Status: code awaiting CI/security review and real-device acceptance. **Not family sharing or a release candidate.**

## Intent and constraints

- Dedicated active project: `little-rest-stage-jh-261020`; `eur3` Firestore
  Native Standard database, previously verified as its single Spark free database.
  Billing is disabled and unlinked. **Never attach billing or upgrade to Blaze
  without the owner's explicit consent.**
- Android app: `com.analienx.baby_sleep_tracker.staging`, registered as a
  separate Firebase app so the existing `com.analienx.baby_sleep_tracker`
  preview installation and test entries are not overwritten.
- Apple staging test uses the registered iOS bundle `com.analienx.babySleepTracker`.
  A Mac, Xcode signing and separate physical iPhone acceptance are still needed.
- Opt-in debug flag: `--dart-define=USE_PERSONAL_STAGING=true`, plus
  `--dart-define-from-file=private/personal-staging.json`. No default build
  connects to staging, and release-mode staging is explicitly blocked.
- Android and iOS use distinct SDK API keys, never one shared key.

## What works on Spark

The new `personalSleep/{uid}/operations/{opId}` scope uses the existing
immutable sleep ledger with Firestore's native offline persistence and live
snapshots; every write retains its actor UID and revision history. The
Firestore Security Rules grant the authenticated user access **only to their own
journal**. A separate `FirestoreSleepRepository.personal` adapter reuses
the fully-tested conflict/overlap logic. No family membership can be
self-granted. The explicit owner-only delete permission exists solely for
a client-initiated account-erasure operation; normal UI edits remain immutable
journal appends.

Firebase Authentication preserves the anonymous UID over process restarts.
The Account and Recovery screen can link email/password (minimum 12 chars),
send verification or reset emails, and restore an existing account only after
the empty anonymous session has been verified on the server. Protecting an
already populated anonymous account keeps its UID and journal. The deletion
flow reauthenticates password users, waits for pending writes, deletes private
documents in bounded batches with server acknowledgement, confirms the
collection is empty, deletes the Auth account and attempts cache clearing.
A failed cache clear is disclosed. This cannot replace independent G2
data-deletion review or a server-side deletion service for production.

Visual updates use explicitly contrasted Material 3 tokens: deep indigo
primary, sage secondary, warm neutral surfaces, readable body/icon colors,
dark-theme preservation and an Android Roboto override against OEM font
substitutions. Light/dark screenshot goldens and color contrast tests should
pass before distributing a new build.

## Deliberately not implemented on free staging

**No secure family calls are deployed.** Household creation, caregiver
invitations/revocation, and recursive family/account deletion require the
separate six trusted callable Cloud Functions and hence Blaze (billing),
verified App Check, required function secret, account-deletion website, and
an independent security approval. We do not quietly replace a trusted
server-issued invitation with client-editable Firestore membership or public
codes. No TTL policies are deployed on Spark. Staging is single-account,
not a private family sync product. Do not record real child information until
privacy and real-device security reviews are complete.

## Reproducible Android staging build

GitHub Actions workflow: `.github/workflows/spark-staging-android.yml`.
On Windows the source remains Java-free; all Android compilation happens
on GitHub runners. Workflow variables/secrets required before enabling:

- GitHub Actions secret `LITTLE_REST_STAGING_CONFIG_B64`: UTF-8 JSON
  `personal-staging.json` encoded as Base64.
- `LITTLE_REST_STAGING_P12_B64`: Base64 of stable debug-only PKCS#12 keystore,
  configured with alias `little-rest-staging`.
- `LITTLE_REST_STAGING_P12_PASSWORD`: associated keystore password.
- Actions variable `LITTLE_REST_STAGING_ENABLED=true` *after* all three
  secrets have been securely configured by the authorized operator.

The signed Android QA package is produced with the environment switch
`LITTLE_REST_STAGING_BUILD=1`, which adds `.staging` to `applicationId`.
The key is **not** a Play Store signing identity. The same staging keystore
must be retained and reused for updates, or Android will reject upgrades.
Never commit that keystore, password or private files. Staging's SDK keys
are public Firebase identifiers, but keeping them in a repository secret
limits accidental misuse by bots and test scripts.

The project's QA host keeps a private staging config and keystore under
`C:\\Workspace\\artifacts\\baby-sleep-tracker\\firebase-staging`. Do not
commit them to Git, and do not add the keystore to a public workflow artifact.

### Android smoke + acceptance

1. Review CI and immutable private journal security rules in the Firebase
   emulator, including unauthenticated/other-UID reads, actor forgery,
   update denial and self-erasure.
2. Deploy reviewed `firestore.rules` only, with explicit `--project
   little-rest-stage-jh-261020`. Do **not** deploy TTL/index definitions.
3. Install signed staging APK alongside preview. Test first anonymous login,
   Start/Stop, History/Trends, offline operation, force-stop/relaunch, reconnect
   pending→synced, then email-linking and recovery on another device.
4. Test delete with a **synthetic** account only and verify server and local
   cleanup. Audit accessibility and light/dark screens.
5. Only promote to a separate paid production project after G2/G3 gates and
   billing consent. Never replace staging with an insecure family workaround.
