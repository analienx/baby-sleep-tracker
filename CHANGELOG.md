# Changelog

Little Rest uses [Semantic Versioning](https://semver.org/). Mobile build metadata is appended after `+`; pre-release builds are **not** production-approved. Product screenshots and summaries describe reviewed capabilities, not deployment guarantees.

## [0.2.0-beta.1] — 2026-10-21

**Pre-release quality milestone; no public store distribution and no real infant data.**

### Added
- Premium, calmer Material 3 interface for Today, History, Trends and Settings, with bundled **Inter** typography independent of Android OEM font themes.
- Android staged Firebase Spark **single-account** journal: private per-UID immutable sleep operations, offline Firestore persistence, cache/pending/synced indicators, export and account-protection flow.
- Complete **family backend implementation** in the separate opt-in F2 environment: server-authorized household creation, email-verified caregiver invitation and redemption, member revocation, shared immutable timeline, conflict resolution, verified account/household deletion and quotas.
- Reproducible Python + GitHub Actions signed staging build and isolated `.staging` install; no local Java dependency.
- First-party product landing page with genuine **empty-state Android app screenshots**, editorial hero, truthful install status and architecture diagram. Screenshot provenance documented.

### Changed
- Active **Sleeping now** and ready-to-start hero cards now follow the selected **light or dark theme**. Light mode uses warm lilac surfaces and dark high-contrast text rather than the always-night gradient; dark mode retains the night palette.
- Primary sleep action now uses theme-appropriate filled-button colors and text; the backdate action uses visible foreground in light mode.
- Family onboarding adopts the same branded theme tokens as the main application. Family settings remain fully interactive **only when a verified family backend and family context are configured**.
- README rewritten for a user-first experience. Previous comprehensive engineering documentation retained as `README_DEVELOPER.md`.
- Android version name `0.2.0-beta.1`, build number `2`; signed QA APK is **not a production signing identity**.

### Fixed
- Android staging launch now resolves the actual Flutter `MainActivity` namespace rather than assuming it matches the suffixed application ID.
- Client-side personal-account deletion fences same-device writes and blocks stale UI during erasure, with recoverable failure feedback.
- Android OEM handwriting-font substitution for main UI text. Main CTA style now explicitly uses the bundled app font.

### Verification
- GitHub runner Flutter analysis/tests, Android build and iOS **simulator** build; Firebase Rules adversarial tests; synthetic personal and family emulator E2E; light/dark visual tests; and four Python deployment unit tests.
- Signed Firebase Spark QA APK installed/launched on a connected Android 16 phone without replacing the existing preview.
- Real app screenshots contain no infant records, accounts or personal notifications.

### Deliberately not enabled
- **Real multi-caregiver family sync is NOT live on Spark.** The secure Cloud Functions are not deployed: the existing Spark project has no billing and Firebase requires Blaze for Cloud Functions. Do not swap in permissive Firestore membership rules.
- Physical two-parent device QA, iPhone distribution/signing, App Check verification, independent privacy/security approval and G2/G3 signoff are incomplete.
- Do **not** publish this version to Google Play or App Store or use it for real baby data until the release gates are approved.

### Upgrade and compatibility
- Android QA package: `com.analienx.baby_sleep_tracker.staging`, updated with the same stable staged signing key; original `com.analienx.baby_sleep_tracker` remains separate.
- Storage mode is chosen at **build time**; default preview is volatile, personal Spark is separate, family backend is separate. These modes do not automatically migrate accounts or combine journals.
- Do not delete or clear app data as a distribution or migration strategy. Protect the personal UID with email/password before reinstalling.

More: [release detail](docs/releases/0.2.0-beta.1.md) · [staging instructions](https://github.com/analienx/baby-sleep-tracker/blob/feat/spark-personal-cloud-light-ui/docs/SPARK_PERSONAL_STAGING.md) · [F2 family implementation](https://github.com/analienx/baby-sleep-tracker/blob/feat/spark-personal-cloud-light-ui/docs/F2_IMPLEMENTATION.md).
