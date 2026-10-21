#!/usr/bin/env bash
set -euo pipefail

mkdir -p e2e-evidence
if ! flutter test integration_test/personal_emulator_test.dart \
  -d emulator-5554 --no-pub \
  --dart-define=USE_PERSONAL_EMULATOR=true \
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2 \
  -r expanded; then
  adb exec-out screencap -p > e2e-evidence/personal-e2e-failure.png || true
  adb logcat -d -t 400 > e2e-evidence/personal-logcat-failure.txt || true
  exit 1
fi
adb exec-out screencap -p > e2e-evidence/personal-e2e.png
