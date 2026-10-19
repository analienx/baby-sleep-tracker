# F0 foundation — evidence and open review gate

**Scope:** Issues [#2](https://github.com/analienx/baby-sleep-tracker/issues/2),
[#3](https://github.com/analienx/baby-sleep-tracker/issues/3).
**Blocking gate:** [G0 #4](https://github.com/analienx/baby-sleep-tracker/issues/4).
**Decision:** Pending independent review, final macOS CI evidence and explicit
approval in gate #4. The first Android/quality workflow was green.

## Implemented for the first review

- Flutter 3.47.7 Android/iOS bootstrap (default package ID currently
  `com.analienx.baby_sleep_tracker`; final production app identity is not yet
  approved).
- Three-screen Today / History / Trends shell with go_router; Riverpod
  dependency seams for clock, actions and repository.
- Light/dark design tokens and low-glare hero, readable empty states, large
  primary action, visual preview warning and semantics.
- Intentionally **volatile** preview repository, not a disguised offline store.
  Real F1 storage/Undo/backdate/edit and F2 Firebase/Auth are not present.
- UTC interval domain model and union-based 24-hour aggregation with unit tests
  for midnight, Prague DST shift, time-zone change and overlapping intervals.
- Source-pinned GitHub Actions for formatting, analysis, unit/widget/golden
  tests, Android debug APK, unsigned iOS simulator compilation and secret
  scanning; no store publishing, cloud deployment or credentials.

## Gate evidence to record before G0 may pass

| Verification | Status |
| --- | --- |
| Clean Flutter 3.47.7 dependency lockfile resolution | Passed in [CI #2](https://github.com/analienx/baby-sleep-tracker/actions/runs/39218592050) |
| `dart format`, `flutter analyze`, 17 Flutter tests (including goldens) | Passed locally and in [CI #2](https://github.com/analienx/baby-sleep-tracker/actions/runs/39218592050) |
| Android debug CI artifact and exact run SHA | Passed — [CI #2](https://github.com/analienx/baby-sleep-tracker/actions/runs/39218592050), code `dca9dbae8c4b6dd6e391c3736978801533e2a0a0`, debug artifact `12170429647` (7-day retention) |
| Light/dark goldens and TalkBack/VoiceOver semantics inspection | Goldens and widget semantics passed; independent device inspection pending (goldens use Flutter test fonts) |
| Flutter iOS project generated; unsigned simulator build | Pending macOS CI |
| Actual iOS simulator launch and real-device interaction | Not verified (device review required) |
| Secret scanning and no real child PII | Gitleaks passed in [CI #2](https://github.com/analienx/baby-sleep-tracker/actions/runs/39218592050); reviewer privacy inspection pending |
| Independent P1/P2/P3 review recorded in gate #4 | Pending |

## Boundary / known gaps

- **F1 (not a completed F0 promise):** Durable Firestore offline cache,
  one-tap Undo, backdate, manual history edits and session reconciliation.
- **F2 (not configured):** Firebase project EU region, authentication, household
  membership, trusted invitations and security rules.
- **F3/F4:** Final logo/app icon, multilingual polish, accessibility testing on
  physical devices, signing and distribution.

Do not close G0 because code exists, or accept F0 based only on local tests.
The reviewer should record findings with severity, reproducible evidence,
mitigations and an explicit gate decision in issue #4.
