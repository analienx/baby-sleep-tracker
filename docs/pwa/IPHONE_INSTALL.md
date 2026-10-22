# Little Rest on iPhone — Home Screen web app (Spark QA)

**Channel:** 0.2.0-beta.2 iPhone PWA candidate · [PR #33](https://github.com/analienx/baby-sleep-tracker/pull/33)
**Host:** https://little-rest-ios-qa.web.app (dedicated Firebase Hosting site)
**Backend:** existing `little-rest-stage-jh-261020` Spark Auth + Firestore, **no Cloud Functions/Blaze**.
**Data policy:** synthetic QA only until Safari physical-device privacy/restore and G2/G3 acceptance.

## Install on iPhone (once the web deployment is live)

1. Open **https://little-rest-ios-qa.web.app** in Safari.
2. Tap the Share menu and **Add to Home Screen**.
3. Turn on **Open as Web App** and tap Add.
4. Launch **Little Rest from its Home Screen icon**. Use it from the icon, not a Safari tab, so the identity and offline storage remain consistent.
5. In the app: **Settings → Account and recovery**, link and verify an email/password. *Never use an anonymous test account for long-term data or transfer across devices.*

To pair with Android, each phone uses a separate email-verified account. Android owner: copy the iPhone caregiver UID into **Settings → Family sharing → Approve caregiver**. iPhone: enter the Android owner's UID in **Join shared journal**. Verify both UIDs out of band. The iPhone must be online to verify initial membership.

## Why this is not equivalent to the native iPhone build

- No Apple Developer fee, seven-day signature expiry, TestFlight or App Store needed.
- It has a home-screen icon and fullscreen Flutter UI, but iOS may suspend it when backgrounded.
- Firestore enables persistent IndexedDB and the service worker caches its app shell **after online installation**. Safari may evict website data or revoke storage; an offline write may be lost if the OS purges the app before reconnect. **Never promise automatic background sync.**
- Use **Synced** server status before closing when a record matters. Offline pending is not safely backed up to Firebase.
- Installing from Safari may create separate storage from your existing browser context. Sign into the same verified email account rather than assuming anonymous state transfers.
- Do not open links to baby records from an unmanaged/shared device. Web Firestore cache may persist after browser exit; use a personal trusted iPhone.

## Technical architecture and deployment

- This is the **same Flutter app**, built with `USE_PERSONAL_STAGING=true`, `USE_SPARK_FAMILY_LITE=true`, `USE_IOS_PWA=true`.
- Web platform uses `cloud_firestore` `Settings(persistenceEnabled:true, webPersistentTabManager: WebPersistentMultipleTabManager())` and checks IndexedDB availability before initialization.
- The custom PWA service worker precaches **same-origin compiled app assets only**; it explicitly never caches Firebase service requests, auth responses or API traffic.
- Browser exports use `XFile.fromData` rather than `dart:io`. Native Android export remains unchanged via a conditional import.
- `web/firebase-staging.defines.json` contains only the *public* Firebase Web SDK options for the separately registered QA web app; it must never contain a Firebase service-account private key, Android signing keystore or Firebase Auth credentials. Firebase Security Rules, not public SDK keys, control authorization.
- `firebase.pwa.json` targets the **different Hosting site** `little-rest-ios-qa` and cannot replace the existing default account-deletion website when used with `--config firebase.pwa.json --only hosting`.

CI builds the exact versioned bundle and uploads `little-rest-ios-pwa-staging-<SHA>` as a GitHub Actions artifact. It does **not** automatically deploy demo assets. For approved staged rollout, use the downloaded artifact's `build/web` contents and run:

```powershell
firebase deploy --config firebase.pwa.json --only hosting --project little-rest-stage-jh-261020 --non-interactive
```

Only deploy when the PWA build has passed GitHub CI and browser smoke, and confirm the *site field* is `little-rest-ios-qa`. Do not run a generic `firebase deploy` (that might deploy other resources).

## Still required for real family usage

- Safari iPhone physical **Add to Home Screen → Start/Stop → force-close/reopen → offline/reconnect → verify server ACK**, plus family invite and revocation on Android + iPhone.
- Verify explicit identity recovery, email verification, export and deletion in installed Home Screen context.
- Enable Firebase App Check on the registered web app using reCAPTCHA Enterprise **before production** (Spark supports reduced scoring granularity); configure allowed domain and monitor Auth/Firestore usage.
- Independent privacy/security acceptance for offline caches and compromised/lost devices.
