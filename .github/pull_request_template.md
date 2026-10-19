# Summary
<!-- What changed, for whom, and why? Keep v1 strictly sleep-focused. -->

Closes #

## Phase / gate
- [ ] F0 / G0
- [ ] F1 / G1
- [ ] F2 / G2
- [ ] F3 / G3
- [ ] F4 / G4

## Functional acceptance
- [ ] The linked issue's acceptance criteria have been verified.
- [ ] Normal, empty, error, offline, restart and retry states relevant to this change are handled.
- [ ] Data/time calculations use persisted UTC instants and deterministic tests where relevant.
- [ ] User-facing operations offer clear feedback; pending local write is not represented as synced.
- [ ] The feature remains usable with large text, one hand and nighttime contrast.

## Security and privacy
- [ ] No credentials, API private keys, signing material or real child data are committed.
- [ ] Family access and least-privilege rules are validated for any new document/function.
- [ ] Unauthorized access, revocation and client-field tampering tested where applicable.
- [ ] Crash/log/analytics output does not include child names or raw sleep timelines.

## Tests and evidence
- [ ] `flutter format --set-exit-if-changed .`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] Firebase emulator/rules tests (if affected)
- [ ] Android/iOS build or physical-device smoke test (if relevant)
- [ ] Screenshots/video for visual changes, with synthetic data only
- [ ] CI runs and negative-case test evidence linked below

**Evidence links:**

## Independent review
- [ ] Correctness, concurrency, security, accessibility and UX impacts considered.
- [ ] P1 findings resolved before gate acceptance.
- [ ] P2 findings have mitigation, owner and follow-up ticket.
- [ ] P3 findings documented/deferred deliberately.

**Known limitations / tradeoffs:**

**Reviewer and gate decision:** Not yet reviewed

> A merged PR does not close a phase gate. The matching G0–G4 issue needs its own review evidence and signoff.
