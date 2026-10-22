#!/usr/bin/env bash
# The only Java/Android emulator work runs on ephemeral GitHub runners.
set -euo pipefail
mkdir -p e2e-evidence
if ! flutter test integration_test/spark_family_lite_emulator_test.dart \
  -d emulator-5554 --no-pub \
  --dart-define=USE_PERSONAL_EMULATOR=true \
  --dart-define=USE_SPARK_FAMILY_LITE=true \
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2 \
  -r expanded; then
  adb exec-out screencap -p > e2e-evidence/family-lite-failure.png || true
  adb logcat -d -t 450 > e2e-evidence/family-lite-failure-logcat.txt || true
  exit 1
fi
echo "Spark Family Lite two-Auth-SDK Android integration E2E passed."
