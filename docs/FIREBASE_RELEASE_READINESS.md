# Firebase release-readiness pass — 20 October 2026

**Status: code prepared for review; not a production deployment or G2/G3 approval.** This release configuration is opt-in. Normal application startup continues in volatile preview mode. No production Firebase project ID, service-account credential, child record, signing key or App Check site key is committed.

## Implemented Firebase protections

| Boundary | Implementation | Readiness / unresolved external dependency |
| --- | --- | --- |
| Android/iPhone application attestation | FlutterFire App Check 0.5.0: Play Integrity; App Attest with DeviceCheck fallback | Register each signed mobile app in the Firebase Console. Verify legitimate devices before enforcement. |
| Callable access | `enforceAppCheck: true` on all deployed Cloud Functions; Firebase emulator only bypasses attestation | Install valid provider keys and Apple entitlement; production Functions reject missing token. |
| Account control | Email/password credential linking retains anonymous UID; verification email; verified email required for invitations | Enable both anonymous and email/password providers; configure email template/sender and 12-character password policy. |
| Family security | One-time 256-bit invitation codes hashed server-side; 24h validity, server-transaction redemption; owner-only invites, 5 issues per authenticated UID and 30 per IP per UTC day; 2 household creations per UID and 10 per IP | Transactional quotas use secret-peppered hashed identities. Mobile caches on revoked devices **cannot** be remotely wiped. |
| Sleep journal | Immutable create-only operations, actor UID matching, parent type/size bounds; deny-by-default Rules, household deletion fence | Requires two physical devices to prove intermittent-network behavior and UX. |
| Household-data deletion | Owner-triggered immediate access fence; recursive children/invitation/member/profile deletion; owner retry after interruption | Deleting household **alone** intentionally keeps Firebase Auth sign-in. |
| **Auth account deletion** | Separate mobile/web callable; credential reauthentication (within 5 min); owner must explicitly agree to delete whole household; caregiver removes identity and membership, preserving pseudonymous shared journal | Firebase Auth account deleted by Admin SDK. Pending deletion markers **do not expire** on failure; after confirmed deletion, a 24h tombstone prevents stale-token creation and is TTL eligible. Cloud/offline cache limitations disclosed. |
| Device cache after account deletion | Mobile signs out, terminates Firestore, attempts `clearPersistence`, then requires app restart; failure is explicitly disclosed | Confirm on real Android and iOS devices; previously shared exports/other phones cannot be revoked retroactively. |
| External account deletion | Firebase Hosting-only self-service page signs in with ephemeral session and calls same verified deletion backend | Must register Web App + reCAPTCHA Enterprise App Check, replace `hosting/config.js` placeholder and deploy a working URL before Play Store submission. Hosting deployment fails closed while placeholder remains. |
| Privacy/retention | `users` only self-readable, `accountDeletions` and `familyRateLimits` unreadable client-side, `familyInvites` secret, no Firebase Storage, Analytics or Crashlytics required | Explicit privacy policy must describe pseudonymous historical actor UID, retained offline copies, TTL timing and Firebase processing geography. |

## Spark staging provisioned — 20 October 2026

**Nonproduction, synthetic data only.** The dedicated Firebase project
`little-rest-stage-jh-261020` is ACTIVE and Firebase-enabled. Cloud Billing
reported `billingEnabled=false` and no linked billing account. No Blaze
upgrade has been approved or performed.

- Registered package IDs: Android `com.analienx.baby_sleep_tracker`; iOS
  `com.analienx.babySleepTracker`; separate Web app reserved for a future
  account-deletion page. This registration does not constitute App Check or
  store signing approval.
- Created the sole free-tier Firestore Native **Standard** `(default)`
  database in `eur3`, with PITR disabled; its free-tier flag is true.
  Deployed only `firestore.rules` from this review branch and confirmed server
  compilation and release. **Do not** deploy the repository's TTL field
  policies on Spark: [TTL deletes require billing](https://firebase.google.com/docs/firestore/pricing).
  The `firestore.indexes.json` TTL definitions are for later, reviewed Blaze
  production deployment, not this free staging project.
- Enabled anonymous and email/password providers, required passwords for email
  sign-in, confirmed improved email privacy, and enforced a 12-character
  minimum password policy using the Identity Toolkit project configuration.
  Verification email sender branding/templates remain to be reviewed.
- Downloaded Android, iOS, and Web public app config into an **ignored**
  `private/` folder in the isolated staging checkout; assembled
  `private/family-staging.json`. Android and iOS use **different API keys**:
  supply `FIREBASE_ANDROID_API_KEY` and `FIREBASE_IOS_API_KEY` separately.
  The old single `FIREBASE_API_KEY` define is not supported.
- **No callable Cloud Functions deployed:** the six secure family operations
  need Blaze. Live family onboarding, invitations, deletion, and the hosted
  deletion page are **not functional** on Spark. The local
  `demo-little-rest` emulator environment is entirely separate and must not
  be confused with the real staging project.
- The portable local Java runtime, its ZIP, and Firestore emulator JAR were
  deleted from the Windows test host at the user's request. Firebase CLI and
  the USB debug APK remain. For full family E2E use the pinned GitHub
  Actions emulator runners, or later arrange a separately approved local
  testing environment. A physical Android device is not yet connected.
- **Do not use real baby information** before G2 privacy/security and G3
  usability reviews. Do not infer production readiness from Firebase project
  creation, rules deployment, or green synthetic GitHub CI.

For future paid production: use a **separate** Firebase project, signed app
registrations and App Check, production secret `FAMILY_ABUSE_PEPPER`, approved
privacy policy and retention, TTL, and the required deletion URL. None of
those production changes happened during Spark provisioning.

## Provision a **new**, dedicated production Firebase project

1. Select and record **project ID**, **billing owner**, and Firestore default database location before creation. Prefer an EU location such as `eur3` (multiregional) if its cost/availability trade-off is acceptable; Functions are pinned to `europe-west1`. Database location is effectively immutable. Enable a billing plan that supports Cloud Functions v2 and set Cloud Billing budget/alerts.
2. Register the **real** Android package `com.analienx.baby_sleep_tracker` (verify `android/app/build.gradle.kts`) and the final iOS bundle ID (verify Xcode project). Configure relevant Android signing SHA-256 and Apple App Attest capability/entitlements in developer accounts. Separate debug/test identities from production. Register a Web App for the deletion URL as well.
3. Authentication → Sign-in method: enable **Anonymous** and **Email/Password**, configure verified sender/custom email templates and password policy of at least 12 characters. Enable email enumeration protection and abuse controls. Configure authorized domains for the hosted deletion URL.
4. Firestore: create default database in production mode; deploy **only** `firestore.rules` from this repository, not `firestore.dev.rules` (legacy insecure development rules). `firestore.indexes.json` has no composite indexes required yet. Do not enable permissive Storage rules or unrelated Firebase services.
5. App Check: register Android Play Integrity, Apple App Attest/DeviceCheck, and Web App reCAPTCHA Enterprise. Enable attestation testing on signed physical devices and the hosted deletion page. Functions callable enforcement is configured in code; then enable Firestore enforcement in Console **after** successful legitimate-client metrics. Do not deploy a bypass/debug-provider production build.
6. Deploy the three TTL field policies specified in `firestore.indexes.json`: `familyInvites.expiresAt`, `familyRateLimits.expireAt`, and `accountDeletions.expiresAt`. Firestore TTL is **eventual** (often up to 24h after expiration); correctness does not depend on it—the application rejects expired invites and keys quota windows by day. Pending account deletions have **no expiration timestamp** until Auth is confirmed deleted; completed deletion tombstones then remain for 24h. They contain only a UID and timestamps, not email or child data. Validate TTL activation before sign-off.
7. Replace `hosting/config.js`'s `appCheckSiteKey` with the Web App's **public** reCAPTCHA Enterprise site key. Do not commit private reCAPTCHA secrets. Firebase Hosting supplies `/__/firebase/init.json` with the public Web App configuration at runtime. Verify the deletion page on the final public URL. The repo intentionally rejects Hosting deploys while the placeholder exists.
8. Provision the function secret `FAMILY_ABUSE_PEPPER` using `firebase functions:secrets:set FAMILY_ABUSE_PEPPER --project <verified-project-id>`. Generate a unique random value of at least 32 bytes; never put it in git, a mobile build, Hosting, or plaintext `.env`. The secret is bound to every callable in `functions/index.js`. Review Secret Manager IAM and pricing. For **emulator-only** tests, `functions/.secret.local` may provide a disposable test pepper; never reuse it in production.
9. Put the public Firebase mobile identifiers in ignored `private/family-prod.json`, based on [`firebase-prod.example.json`](firebase-prod.example.json). No service-account JSON is needed by mobile code. Native app is activated only with `--dart-define=USE_FAMILY_PRODUCTION=true --dart-define-from-file=private/family-prod.json`.
10. Before production deploy, run the local Auth, Firestore and Functions emulator matrix and Flutter CI below; review Rules and Admin SDK callables independently. Grant only the runtime IAM roles required for Firestore and Firebase Auth deletion; don't use downloadable permanent service-account keys. Stage a no-child-data smoke test in a dedicated nonproduction project first.
11. After manual G2 signoff, deploy in a controlled change window using an **explicit** `--project <verified-id>` and `--only firestore,functions,hosting`. Verify deployed rules, Functions region, App Check accept/reject metrics, external deletion URL, account deletion, recovery, and Firestore cleanup. The repo does not auto-deploy.

## Reproducible verification

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
npm ci --prefix functions
npm run check --prefix functions
npm exec --prefix functions -- firebase emulators:exec \
  --project demo-little-rest --only auth,firestore,functions \
  "npm test --prefix functions"
node --check hosting/deletion.js
node scripts/check-hosting-ready.mjs  # intentionally fails until production site key is configured
```

The integration tests must cover distinct authenticated UIDs, unverified email denial, invitation redemption/replay, forged writes, revocation, historical journal retention after caregiver account deletion, owner-only deletion, actual Firebase Auth identity removal, nested child cleanup, retry and Rules denial while deletion is in progress. The web deletion URL is not proven by emulator-only tests.

## Explicit remaining release gates

- **G0/G1:** Existing upstream PR and physical compact-layout/offline quality gates are not auto-approved by this Firebase pass.
- **G2:** Independent security review of real project IAM, Firestore/App Check enforcement, identity/deletion/TTL behavior; Android+iPhone two-parent offline, reconnect order, app kill/restart, revoke, re-login and device-cache wipe.
- **G3:** Cross-platform release UX, accessibility, internationalization, privacy policy, real store deletion URL, export/share sheets and signing verification.
- **Production changes:** Creation, billing, domain, App Check registration, TTL policy, real email sender, live deploy and store publication require a verified project and owner approval. None are assumed.

Reference: [Firebase Flutter App Check](https://firebase.google.com/docs/app-check/flutter/default-providers), [Callable App Check enforcement](https://firebase.google.com/docs/app-check/cloud-functions), [Firestore offline cache](https://firebase.google.com/docs/firestore/manage-data/enable-offline), [Auth deletion/reauthentication](https://firebase.google.com/docs/auth/flutter/manage-users), [Firestore TTL](https://firebase.google.com/docs/firestore/ttl), [Google Play deletion policy](https://support.google.com/googleplay/android-developer/answer/13327111).
