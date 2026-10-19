# Implementation plan — Baby Sleep Tracker v1 (family-first)

**Status:** Accepted planning baseline (2026-10-19). Implementation has not started.
**Repository:** `analienx/baby-sleep-tracker`
**Target:** Android + iPhone, one household, one child by default, two parents initially, optional invited caregivers.
**Principles:** One-tap interactions, offline recording, clear ownership, correct time arithmetic, privacy, accessible night use.

## 1. Product contract

### Primary jobs-to-be-done

1. While holding a baby, start sleep with one reachable touch, with an optional quick backdate.
2. On waking, finish the current sleep session with one touch; current awake time becomes visible.
3. Correct a missed or mistaken event without re-entering unrelated data.
4. See what happened in a rolling 24-hour window: sleeps, awake periods, total sleep and session count.
5. A second signed-in caregiver sees and may modify the same family timeline; offline operation is never blocked once the device has been onboarded.
6. Restore previously synced records after phone replacement; export and delete data on demand.

### Explicit v1 non-goals

- Feeding, diaper, pumping, growth, medication, or full baby-care journal.
- Passive detection from microphone/camera/wearables, white noise, sleep training, sleep scores, predictions, medical guidance, diagnostic correlations or generalized wake-window prescriptions.
- Public social features, multi-tenant business accounts, subscription/billing, home assistant integration.
- Mandatory home widget, Live Activity, Apple Watch or Wear OS in v1.

### User-flow acceptance targets

- Launch into today's screen. One primary action reflects sleeping vs awake state.
- Start/stop records immediately in the on-device cache, irrespective of cloud round-trip.
- Two taps or fewer from Today to quick-backdate; corrections reachable without hidden gestures.
- Successful local action shows immediate visual/haptic confirmation and offers Undo.
- Offline/sync/conflict states are legible, and never disguised as confirmed cloud sync.
- The app is usable one-handed, with large hit targets, VoiceOver/TalkBack labels and system dynamic font support.
- The first-time flow does not require a password: start anonymously; link a durable account before inviting others, changing devices, or enabling restore.

## 2. Architecture (ADR-0001)

| Concern | Decision | Why |
| --- | --- | --- |
| Mobile | Flutter + Dart | Consistent custom UI and shared business logic |
| UI | Flutter widget composition, Material 3 foundations, custom tokens | Modern, accessible, platform-adapted design |
| State | Riverpod, feature-scoped providers | Testable state and lifecycle |
| Navigation | go_router | Small explicit screen map |
| Data layer | `SleepRepository` interface and Firestore implementation | Keep UI separate from persistence |
| Local persistence | Firestore's native mobile offline persistence | No custom dual-database sync engine in v1 |
| Cloud | Cloud Firestore in a deliberately selected EU location | Realtime sharing and managed mobile SDK |
| Identity | Firebase Auth: anonymous entry, account-linking through supported provider | Frictionless trial with durable restore/share |
| Membership | Household-scoped Firestore Security Rules | Deny by default for any non-member |
| Invitation | Minimal Cloud Function or equivalent trusted function | Single-use expiring invite redemption; no self-granted membership |
| CI | GitHub Actions | Automated lint, test, rules and build verification |
| Telemetry | Crash-only diagnostics where justified, opt-in analytics if ever added | Privacy by default |

No bespoke REST API, no always-on timer service and no separate SQL store are justified for v1.

## 3. Data contracts and invariants

### Firestore paths (draft, subject to security-rules proof)

```
households/{householdId}
  members/{uid}                   // role, joinedAt, revokedAt
  babies/{babyId}                 // displayName, dateOfBirth, timezone preference
    sleepSessions/{sessionId}     // source-of-truth current record
      actions/{actionId}          // immutable operation/audit record
  invitations/{invitationId}      // server-controlled hashed secret + expiry
```

Do not use child names, emails or other personal identifiers in document IDs. Do not place test data or credentials in a public repository.

### Sleep session

```json
{
  "schemaVersion": 1,
  "id": "client-generated-uuid",
  "householdId": "opaque-household-id",
  "babyId": "opaque-child-id",
  "startedAtUtc": "ISO-8601 UTC instant",
  "endedAtUtc": null,
  "createdByUid": "auth-uid",
  "lastEditedByUid": "auth-uid",
  "revision": 1,
  "createdAtServer": "server timestamp when available",
  "updatedAtServer": "server timestamp when available",
  "deletedAtUtc": null
}
```

`startedAtUtc` and `endedAtUtc` represent real event instants recorded by the device, distinct from ingestion timestamps. A null end means active. `[start, end)` intervals are used consistently. No negative or zero-length completed sessions. Rejected invalid times are explained, never silently repaired.

### Mutations, concurrency and deletion

- Each action carries a client-generated idempotency key, actor, event timestamp, base revision and operation type (`start`, `stop`, `edit`, `delete`, `restore`).
- Application performs local Firestore batch writes for an edited session + immutable action record (subject to rules proof). A retry with the same operation ID cannot create a duplicate action.
- Detect competing edits against the same base revision and overlapping sleep sessions. Present a concise conflict resolution UI with both values; never silently erase the evidence of either action.
- Firestore's last-write-wins behavior is **not** conflict resolution; avoid implying that concurrent offline edits are serialized.
- Cross-device 'single active session' is best effort while disconnected. Multiple offline starts must be reconciled after reconnect; do not pretend distributed mutual exclusion is possible.
- Soft-delete first. Export and restore must account for deletion markers; physical purge follows an explicit retention/deletion policy.
- Exactly-once cloud delivery is not assumed. Client mutations must be idempotent. Any server-side projection or validation introduced later must be reproducible.

### Time and reporting

- Persist UTC instants; apply the device/household IANA time zone only to presentation and calendar-day slicing.
- Elapsed durations are computed as `now - persistedStartedAt` while active; no background countdown process is authoritative.
- Rolling 24h sleep is the sum of intersection durations between sessions and `[now-24h, now)`, including an active session capped at now.
- Overlapping sessions must not be double-counted: union occupied intervals while flagging the overlap as a data issue.
- Awake time begins at the end of the latest accepted sleep session; if data is unresolved, label the value provisional.
- DST forward/backward, midnight, device clock changes, travel, locale and 12/24h display must have deterministic fixtures.
- Never infer nap vs night from a rigid age-based threshold. Night/day classification can be a later configurable presentation feature.

### Offline contract

- Once signed in/onboarded, a parent can start/stop/edit with airplane mode enabled.
- A local write is acknowledged as **Saved on this device**; only after remote confirmation as **Synced**.
- On process kill, reopening derives the visible state from cached persisted data.
- After reconnect, pending mutations eventually sync; deterministic conflict detection surfaces ambiguous edits or overlaps.
- There is no promise of recovering unsynced data after app uninstallation, data wipe, or device loss. UI and support text must distinguish this from synced records.
- Initial sign-in and invitation redemption require connectivity; core tracking after onboarding does not.

## 4. UX design specification

### Screen A — Today (the primary experience)

- Header: child name + age, family/profile affordance, subtle sync status.
- Status card has exactly one dominant call to action: `Start sleep` when awake, `Wake up` when sleeping.
- Centerpiece: asleep duration or awake duration in large tabular digits; subdued status icon and timestamp.
- Secondary action: quick backdate (5, 10, 15 minutes) / adjust exact start.
- Below: rolling 24h sleep total, number of sessions, compact segmented timeline.
- Undo toast after actions. No confirmation modal for ordinary Start/Stop; accidental taps are recoverable.

### Screen B — History

- Chronological sessions grouped by local date, with clear start/end and duration.
- Tap session to edit times or soft-delete. Dedicated manual-entry action.
- A session spanning midnight is one record with a readable date/time range.
- Conflicting/overlapping sessions carry a warning and resolution action.

### Screen C — Trends

- Simple rolling 24h total and 7-day sleep totals only if there is sufficient data.
- Avoid normative sleep scores, health claims or authoritative wake-window targets.
- Empty and incomplete-data states are as carefully designed as normal states.

### Settings / Family

- Child nickname and date of birth, optional preferred time zone.
- Family members and invite link/QR flow, revoke access.
- Account linking/restore, export JSON + CSV, privacy/deletion controls.
- Light/dark/system appearance, language-ready strings (English baseline; Czech localization possible).

### Visual tokens

- Calm premium look: warm neutral surfaces, midnight indigo night card, restrained lavender/sage accents.
- Dark mode deliberately low glare, including large primary button and timeline.
- >=44pt iOS / >=48dp Android hit regions, generous spacing, legible contrast, system text scaling, reduced-motion behavior.
- Haptic/visual affordance for every start/stop, explicit error and pending-sync status.
- No decorative imagery that delays interaction, no skeuomorphic baby graphics, no advertising.

## 5. Security and privacy requirements

1. Deny all reads/writes by default. Authorize only current household members and scope every baby/session/action query to that household.
2. Non-members cannot enumerate families or children. Revoked members lose access on the server. Previously cached data on an offline, revoked device cannot be remotely erased instantaneously; do not promise remote wipe.
3. Client cannot grant itself membership, owner role or expanded permissions. Invite issuance/redeem/revoke occurs through trusted, rate-limited function and verified membership.
4. Invite tokens expire, are single use, do not contain child PII and are stored hashed where appropriate.
5. Firestore Rules validate allowed fields and shapes, ownership boundaries, timestamp bounds and delete semantics to the degree feasible. Server-only fields are protected.
6. Automated positive and negative emulator tests cover stranger access, cross-household ID probing, role elevation, modified invitations and revoked members.
7. Choose EU Firestore location deliberately before provisioning; note that this alone does not prove all identity/service processing is EU-only.
8. Export and permanent deletion are available in product. Document retention and backup restoration semantics.
9. No real personal baby records, Firebase service-account files, signing certificates or tokens in the public repo, logs, fixtures or screenshots.
10. Telemetry is minimal; do not record child names or timestamps in crash breadcrumbs.

## 6. Work phases and explicit review gates

### Phase F0: Blueprint and engineering foundation

Deliverables:
- [ ] Flutter app shell and predictable project layout (`lib/app`, `lib/features/sleep`, `lib/data`, `test`).
- [ ] Dependency locking, config separation, themes, navigation, baseline semantics and demo fixtures.
- [ ] CI format/analyze/test workflow; Android debug build; security scanning for secrets.
- [ ] Architectural records and acceptance-test inventory.

**Gate G0 — architecture review (blocking)**
- No unnecessary background services, custom backend, second local database or heavyweight platform-specific framework.
- All repositories/clock abstractions injectable and independently testable.
- `flutter analyze`, formatter, unit tests and Android debug build green in CI, with logs linked in gate.
- ADR, v1 scope and privacy assumptions reviewed; no real baby data in repository.
- A reviewer unaffiliated with the implementation records P1/P2/P3 findings; P1 issues resolved and P2 mitigations recorded.

### Phase F1: Offline single-device vertical slice

**Dependency boundary:** F1 exercises Firestore's native local cache using a development-only Firebase SDK/Auth emulator configuration and a synthetic anonymous test identity. This is not the family production cloud setup. Real project provisioning, durable sign-in, household membership and cloud sync remain in F2. A device must establish the initial emulator/identity session online before airplane-mode testing.

Deliverables:
- [ ] Domain reducer/validation, time interval arithmetic, midnight/DST fixtures.
- [ ] One-tap start/stop, backdate, Undo, persisted active session.
- [ ] History, manual add/edit/delete, clear error messages.
- [ ] Rolling 24h total, session count, awake duration, compact timeline.

**Gate G1 — correctness and offline review (blocking)**
- Airplane mode start/stop/edit works after onboarding.
- Force-stop/relaunch and simulated OS process death do not lose a locally committed session.
- Two rapid taps cannot generate duplicate starts/ends; idempotent operation tests pass.
- Manual edits reject invalid ranges, negative duration and future invalid dates.
- Midnight, DST transitions (including Europe/Prague fall-back), UTC offset change and overlaps have golden test fixtures.
- No recurring background timer service; running display is derived from stored timestamps.
- UI tests show primary action within one tap and Undo within reach.
- Review includes correctness, data loss risks, accessibility and regressions; P1s closed before gate passes.

### Phase F2: Household, identity and sync

Deliverables:
- [ ] Firebase configuration and anonymous-to-durable account linking.
- [ ] Family membership, invitation redemption, role revocation.
- [ ] Firestore query subscription, cache/pending sync indicators.
- [ ] Immutable action records, duplicate-session detection, concurrent-edit reconciliation.
- [ ] Comprehensive Firestore Rules and emulator tests.

**Gate G2 — security and multi-device reliability review (blocking)**
- Two independently authenticated parents on Android and iPhone see and can change the same session when online.
- Both disconnected devices perform overlapping starts/stops/edits; reconnect produces no silent data loss, duplicate counting or undetected overwrite.
- Simulated interrupted uploads/retries preserve idempotency and accurate sync status.
- An unauthorized identity cannot read or mutate any household child or action.
- Revoked users cannot access records on a fresh authenticated server request.
- Invite replay/expiry/cross-family misuse negative tests pass.
- Account restore and migration from anonymous to durable identity preserve existing data.
- Security review explicitly inspects rules and trusted functions; every P1 closed, P2 tracked and accepted.

### Phase F3: Premium experience, data ownership

Deliverables:
- [ ] Finished day/night visual language, high contrast and large controls.
- [ ] VoiceOver/TalkBack, text scaling, orientation/small screens, reduce motion.
- [ ] Trends and empty/loading/error/offline states.
- [ ] Export JSON + CSV, soft deletion/restore, account and child data deletion.
- [ ] Crash diagnostics without child PII, localization-ready UI text.

**Gate G3 — product and accessibility review (blocking)**
- Five-minute fresh-parent usability run: log, undo, add missed nap, edit, inspect total, invite other parent.
- All user journeys work in light/dark, small and large device sizes, and screen-reader navigation.
- Correct behavior when statistics have zero, one, or insufficient sessions.
- Export faithfully reproduces stored sessions and metadata; deletion/revocation behave per policy.
- Error states tell users whether data is locally saved, synced, or conflicting; no ambiguous green success.
- Independent visual review and functional review recorded, with P1/P2 disposition.

### Phase F4: Release hardening and family rollout

Deliverables:
- [ ] Android and iOS real-device build/test, signing kept outside Git.
- [ ] End-to-end offline/online/restart/auth invitation matrix.
- [ ] GitHub Actions release workflow, versioning and changelog.
- [ ] Internal Android distribution and TestFlight (if accounts/signing available).
- [ ] Privacy summary, data deletion instructions and recovery documentation.

**Gate G4 — release review (blocking)**
- No open P1. P2 accepted only with an explicit mitigation, owner and follow-up ticket.
- Android and iPhone devices pass complete smoke test; no simulator-only signoff.
- One real two-caregiver scenario is exercised with synthetic data, offline/reconnect and account recovery.
- Security and privacy checklist signed off; export and deletion tested.
- Build provenance, test artifacts and release notes linked from gate issue; tag `v1.0.0` only when accepted.
- Release is blocked if Firebase project, Apple signing, store/distribution access, or privacy policy dependencies are not configured.

## 7. Test matrix (minimum)

| Case | Automated | Real device |
| --- | --- | --- |
| One-tap Start/Stop + Undo, duplicate taps | Unit/widget | Both OS |
| Kill/relaunch during active sleep | Integration where possible | Both OS |
| Airplane mode start/stop + eventual sync | Emulator/integration | Both OS |
| Parent A starts, B ends | Integration | Android <-> iPhone |
| Both start offline, then reconnect | Integration | Android <-> iPhone |
| Both stop/edit same session offline | Conflict tests | Android <-> iPhone |
| Local midnight, Europe/Prague DST, travel | Pure time unit/golden | Spot check |
| Unauthorized read/write, forged membership | Firestore Rules emulator | N/A |
| Invite expired/replayed/revoked | Function/rules test | Both OS |
| Guest account linking and restore on new phone | Auth integration | Both OS |
| Export/deletion | Unit/integration | Both OS |
| Light/dark, enlarged text, screen reader | Widget/golden/semantics | Both OS |

## 8. CI and review policy

- Pull requests only for implementation. Require `flutter format --set-exit-if-changed`, `flutter analyze`, `flutter test`, Rules emulator tests, secret scanning and Android build after bootstrap.
- Add iOS macOS build to release branches or final gates once signing/test access exists; don't burn runner minutes on trivial documentation changes.
- Every implementation issue links test evidence and at least one relevant negative test.
- Each PR is independently reviewed against functional behavior, concurrency, security, performance, UX and failure modes, not only formatting.
- Issue severity: P1 blocks gate, P2 requires owner/mitigation, P3 can be deferred. No silent acceptance of failing tests.
- Explicitly track unverified assumptions and decisions in issues; avoid claiming TestFlight/Play delivery until accounts/signing exist.
- No GitHub Actions should deploy cloud resources or publish store releases before the corresponding environments/secrets and approvals exist.

## 9. Dependencies and sequencing

```
F0 foundation/CI
   -> F1 time model -> single-device tracking -> history/stats -> G1
   -> F2 Firebase/Auth -> household access -> offline sync/conflicts -> G2
   -> F3 UX/accessibility/export -> G3
   -> F4 device/release hardening -> G4
```

F2 data model/security design starts during F1, but integration of shared sessions follows completion of F1's persistence invariants. F3 design tokens start in F0; advanced polish waits until real flows work.

External setup gates (user action potentially required): a Firebase project, chosen EU data location, platform app IDs, approved Auth providers, and eventually Apple Developer/TestFlight and Android testing access. Do not hardcode credentials or silently provision billable infrastructure.

## 10. Risks and mitigations

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Firestore LWW loses concurrent edits | P1 | Immutable action record + conflict detection + reconciliation tests |
| Claims of offline durability exceed guarantee | P1 | Honest pending-sync UI; explain unsynced loss after uninstall/device wipe |
| Unauthorized household access | P1 | Deny-by-default rules, emulator adversarial tests, server-side invites |
| Incorrect DST/midnight metrics | P1 | UTC intervals + deterministic time-zone test fixtures |
| Initial Auth friction causes abandonment | P2 | Anonymous start, account link only for sharing/restore |
| Design scope overwhelms engineering | P2 | Fixed three-screen v1, strict defer list, early device usability tests |
| Platform signing/store credentials missing | P2 | CI debug builds early; separate release gate; no claimed store availability |
| Firebase vendor dependence | P3 | Repository/domain abstraction + JSON export and schema versioning |

## 11. Definition of v1 success

A two-parent family can record a full week of sleep without lost sessions or confusing interactions, including at least one offline period; retrieve the same accepted timeline on both phones; correct mistakes; understand totals; and export/delete their records. A clean, low-glare, accessible design is a product requirement, not decorative stretch work.

**Next:** Execute F0 issues in GitHub, attaching run/test evidence to their review gate. No application implementation is implied by this planning document.
