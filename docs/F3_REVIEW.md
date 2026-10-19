# F3 corrective review — integrated F2 + F3 draft

This integration is based on F3 PR #26 and the latest F2 PR #25. **G0 #4,
G1 #9, G2 #14 and G3 #18 remain open.** Automated passing tests are not
authorization to deploy a family-data app with real infant records.

## Corrected in this integration

- **P1 — daily usability:** An unresolved historical edit is still warned
  about, but cannot hijack **Start sleep / Wake up** when there are zero or one
  active sessions. Only multiple active records block the primary action.
  A widget regression covers a disputed older nap alongside an active nap.
- **P1 — family integration:** F3 family placeholders now navigate to the F2
  authenticated household onboarding, durable account linking, one-time
  invitations, caregiver management and revocation when family mode is
  enabled. Ordinary preview mode honestly disables these actions.
- **P1 — data portability:** New archive schema v2 exports accepted sessions
  **and immutable revision operations**, actor IDs, tombstones, ancestry,
  competing heads and quarantined/invalid document IDs. JSON and CSV declare
  cloud confirmation and completeness; cached or pending snapshots are **not
  certified backups**. Older projection-only export methods are retained.
- **P1 — export privacy:** Generated files live in a narrowly named app-only
  temporary directory. They expire after one day; an explicit Settings button
  removes them earlier. External share recipients own their separate copies.
- **P1 — household deletion:** Owner-only typed `DELETE` confirmation; server
  transaction immediately fences household access in Firestore Rules; removes
  invitations and member profiles; recursively erases baby documents **and
  their immutable operation subcollections**; atomically removes the owner's
  profile and family root last. Interrupted deletion is locked and retryable.
  Sign-in credentials remain separate.
- **P2 — charts:** Overlapping days are marked and explained on the seven-day
  chart; durations continue to use interval unions.
- **P2 — preferences:** Appearance writes are serialized; stale startup reads,
  out-of-order taps and failed writes cannot silently misrepresent the choice.
- **Visual accessibility:** Existing chart contrast, compact tap target,
  large-text and six theme golden checks remain intact.

## Verified with synthetic data

- [x] Flutter format and static analysis with zero reported issues.
- [x] **78 Flutter domain/widget/golden tests** passed, including the
  historical-dispute and rapid-preference regressions.
- [x] Firebase Auth + Firestore + Functions emulator: two signed-in caregivers,
  one-time invitations, role protection, operation sync, revocation, deletion,
  nested operation and invitation erasure.
- [x] Firestore Rules emulator: strangers, forged actors, invalid ancestry,
  role escalation, and deletion-fenced reads/writes are denied.
- [x] Staged-export cleanup and complete/incomplete archive tests.
- [ ] CI Android debug and unsigned iOS simulator build on **integrated PR
  head** (Linux runner lacks Android SDK and macOS/Xcode).
- [ ] Two physical phones: install/reboot/offline edit/reconnect/conflict,
  invitation/revocation, and permanent deletion walkthrough.
- [ ] Android + iPhone share UI, TalkBack + VoiceOver, dynamic type,
  reduced motion, contrast and tired-parent usability evaluation.
- [ ] Production Firebase setup, backup/retention policy, app signing, store
  compliance, privacy notice, recovery drills.
- [ ] Independent F2/G2 security and F3/G3 product approval.

## Remaining gaps — not approved

1. **Production security:** The family backend is exercised under emulators,
   not deployed to a production project. Offline copies downloaded before a
   caregiver is revoked cannot be remotely erased.
2. **Identity deletion:** Household cloud-data deletion does not delete
   separate Firebase Authentication accounts. In-app credential deletion and
   recent-login reauthentication require implementation before release.
3. **Localization:** The F3 ARB-based shell is English-only, and inherited F1
   Today/History/editor and F2 family screens retain literal strings.
4. **Travel-zone semantics:** Day charts follow the *viewing device's* local
   calendar. Changing its time zone may regroup older sessions even though
   UTC elapsed durations remain correct. A household IANA zone and a viewing
   zone selector remain a separate product decision.
5. **Backup semantics:** An archive reflects a point-in-time Firestore SDK
   listener snapshot, not a transactional global snapshot of every offline
   device. `complete: true` means that this device saw a server-confirmed,
   no-pending-writes journal with no known invalid/quarantined operations.
   Another device may still be holding unsent writes.

## Reproduction

```sh
flutter analyze
flutter test
npm --prefix functions ci
functions/node_modules/.bin/firebase emulators:exec \
  --project demo-little-rest --only auth,firestore,functions \
  'npm --prefix functions test'
```

Use synthetic identities and timestamps only. Never add real baby records,
invitation tokens or Firebase secrets to this public repository.
