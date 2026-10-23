# Little Rest — one installable web app for Android and iPhone

**Status:** private Firebase Spark QA, browser-first mobile distribution. Android native remains a compatible secondary staging channel. **Synthetic test records only** until G2/G3 privacy, real-device Safari, identity and offline recovery acceptance.

**Use the same secure URL on both phones:** https://little-rest-ios-qa.web.app

The `little-rest-ios-qa` name is a legacy Firebase Hosting site identifier, **not an iPhone-only app**. Keeping its origin unchanged preserves existing browser-installed app identity and same-origin offline storage. A future production hostname needs a reviewed account/data migration plan; do not silently move it.

## Install

### Android (Chrome)

1. Open https://little-rest-ios-qa.web.app in **Chrome on Android**.
2. Tap the in-app **Install** suggestion, if Chrome offers one; confirm the native Chrome install prompt. If no prompt appears, open Chrome's **⋮ menu → Add to Home screen → Install** (wording can vary).
3. Open **Little Rest from the home-screen icon**. Chrome with Google Mobile Services typically installs it as a WebAPK; otherwise the browser may create a home-screen shortcut.
4. In **Settings → Account and recovery**, protect the private journal with a verified email/password before switching or losing phones.

### iPhone (Safari)

1. Open the same URL in **Safari**.
2. Tap **Share → Add to Home Screen**, enable **Open as Web App**, then tap **Add**.
3. Launch the icon. Safari does not support Chrome's JavaScript install prompt; the in-app install guide only explains the Share-menu process.
4. Verify email/password before transferring or sharing. A browser tab and Home Screen web app may not inherit the same anonymous session.

### Android, iPhone or desktop browser without installation

You can also use Little Rest directly in a normal browser tab over HTTPS. The data model, baby selector, personal profiles and caregiver sharing use the **same Firebase Spark** authentication/rules and journals regardless of operating system. Installation is a convenience, not a separate backend.

## Why browser-first

- **Single shared Flutter UI**, release, deployment, Firebase Auth and Firestore rules; faster fixes and no Apple provisioning renewals.
- New releases come from exact reviewed, GitHub-hosted web artifacts. The generated service worker caches **only same-origin static app shell files**, never Firebase API responses. Flutter's `main.dart.js` and bootstrap are network-first with stale-HTTP-cache bypass and an offline fallback; Hosting explicitly revalidates the script and manifest.
- Verified email identities give a path for moving between Android/iPhone; separate caregivers use owner-issued grants. Legacy Baby 1 and additional babies continue to have isolated histories.

## Important limitations

1. Offline editing uses Firestore IndexedDB where browser support permits. Mobile browsers **may evict website storage**. A local pending write is not a confirmed cloud backup. **Check that changes say Synced before closing or changing device**. No promise of automatic background sync, continuous timers or push notifications.
2. App switching/backgrounding, standalone safe-area behavior and storage quotas vary across iOS Safari and Android Chrome. Physical-device tests are required before production approval.
3. Internet is needed to first connect/login, verify a newly selected baby or caregiver, and receive server ACK. If an existing profile cannot be verified, the app must block rather than write to the wrong baby.
4. Android native `.staging` and Chrome PWA have **separate app data and possibly separate anonymous UIDs**. Do not uninstall the native app or assume an anonymous profile transfers; link the original account to a verified email and confirm server data first.
5. Web push and Home Screen badge support are not yet implemented or promised. No subscription fee or Firebase Blaze upgrade is required for the current Family Lite stage, though free project quotas are shared.

## Release verification

GitHub workflow: `.github/workflows/ios-pwa-ci.yml` (historical file path), now titled **Little Rest Mobile PWA — Android and iPhone web CI**. Validates Flutter analyzer/unit tests, responsive layout, web release compilation, manifest/worker/install script syntax and produces a versioned exact-source artifact. Deploy with `scripts/deploy_pwa_stage.py --branch feat/multi-baby-spark-family --source-sha <reviewed-green-SHA>` from a clean dedicated worktree. Deployment targets **only** Firebase Hosting site `little-rest-ios-qa` and cannot overwrite the separate account deletion site.

Acceptance needs Chrome Android and Safari iOS installed-app tests: installation; relaunch; online Start/Stop; force-close; offline Start/Stop pending; reconnect and server ACK; child A/B separation; caregiver pairing/revocation; recovered email login; light/dark theme at narrow widths; VoiceOver/TalkBack and long-text touch targets. Record actual evidence and exact source revision in [issue #35](https://github.com/analienx/baby-sleep-tracker/issues/35).

Relevant: [P0 Android lifecycle bug #36](https://github.com/analienx/baby-sleep-tracker/issues/36) · [Draft family PR #34](https://github.com/analienx/baby-sleep-tracker/pull/34).
