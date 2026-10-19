# F3 experience, accessibility and privacy: stacked draft review

This branch is stacked on `feat/f1-history-corrections` (PR #24), which itself
depends on F1 PR #23 and F0 PR #22. **G0 #4, G1 #9 and G2 #14 are not approved.**
Do not merge this branch or close F3 #15–#17 / G3 #18 based only on automated
tests. Do not use any preview records as real infant data.

## Implemented

- **#15 / visual & accessibility:** three-tab navigation retained; gear opens
  privacy/settings instead of adding a fourth tab. Appearance (system/light/
  dark) persists in device preferences. Compact/200% text layouts pin the one
  primary action above the tab bar; a warning never obscures it. Timers are
  derived from UTC records and pause their visual tick while app is backgrounded.
  Existing card colors use low-glare dark surfaces; no custom motion bypasses
  platform reduced-animation settings.
- **#16 / observations:** seven real *local civil days* with UTC boundaries;
  `SleepSummary.between` clips and unions overlapping sessions. Day lengths
  adjust for 23-/25-hour DST changes. An empty day is explicitly **No entries**,
  not `0h` of sleep; today is incomplete. The chart has screen-reader text
  equivalents and no target, score, prediction or medical claim. Initial
  English ARB/Flutter localization pipeline covers F3 and tab labels.
- **#17 / portability:** export of the **accepted visible projection** as
  versioned JSON or UTF-8 RFC-4180 CSV through native share UI, with UTC
  instants and null ongoing end. JSON round-trip tests, zero-data and CSV
  escaping/formula safeguards. Export reads repository state at tap time and
  distinguishes share success/dismissal/unknown results. No analytics or
  crash-reporting SDK records child identifiers or raw timelines.

## Honest limits and gates

1. **P1 dependency / G2:** F2 authenticated household, invitations, access
   revocation, profile, account migration, data-deletion endpoint and secure
   production Firestore rules do not exist in this branch. These controls are
   disabled with explanations; there is **no pretend invite/delete action**.
   Full deletion/revocation behavior must be implemented and verified in F2.
2. **P1 for G3:** Real Android and iPhone share-sheet, screen-reader, tap
   target, dynamic type, contrast, reduced-motion and visual walkthroughs
   remain unverified, as does a fresh caregiver's five-minute journey. Device
   smoke and independent sign-off are required before closing any F3 issue.
3. **P2 localization:** Existing Today/History/F1 editor strings still contain
   literals. Convert them to ARB messages before claiming #16 fully done.
4. **P2 privacy:** `share_plus` stages temporary export bytes in app cache;
   external destinations may retain them. Verify cache lifecycle/removal and
   privacy messaging on real devices before using personal sleep data.
5. **P2 data fidelity:** The repository exposes accepted sessions, not its
   complete immutable operation journal; unresolved edit heads, revisions and
   server history are outside current exports. Improve repository export
   contract when F2 is available, with multi-device concurrency testing.
6. **P2 visual:** Independent visual critique and measured contrast report
   outstanding. Golden tests do not replace device screenshot/gestures.

## Synthetic verification checklist

- [x] Session JSON round-trips exact UTC timestamps, IDs and null ends.
- [x] CSV comma/quote escaping, empty header, formula-like ID protection.
- [x] Seven-day absent/partial days and cross-midnight overlapping totals.
- [x] Europe/Prague spring 23-hour/autumn 25-hour days.
- [x] Compact 320×568, 200% text, one-tap action and semantics assertion.
- [x] Light/dark golden baselines: Today, Trends, Settings.
- [x] Preferences in-memory fake in widget suite; disabled family actions.
- [ ] Android debug APK / unsigned iOS simulator build on this PR's head.
- [ ] Real-device iPhone/Android TalkBack/VoiceOver/appearance/share checks.
- [ ] Firebase two-caregiver household, export, deletion, revocation E2E.
- [ ] Independent P1/P2/P3 review decision; G3 approval.

## Review/operation notes

- Do not rely on a Flutter background timer: both Today and Trends use saved
  UTC times and recompute on resume. The minute ticker exists only to refresh
  an open Trends screen when an active record crosses a minute boundary.
- A single session spanning midnight is never split in storage. Bar metrics
  represent *observed* seconds clipped to each civil day; no entries do not
  imply wakefulness.
- Export is a point-in-time read of the accepted projection. It is not a
  cloud-confirmed, transactional cross-device snapshot. Pending sync status
  in the preview/emulator is not proof of server persistence.
- This is a public source repository. Never check in real names, email
  addresses, sleep timelines, Firebase config, tokens or private exports.
