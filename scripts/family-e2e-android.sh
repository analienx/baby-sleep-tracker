#!/usr/bin/env bash
set -euo pipefail

mkdir -p .e2e
# Validate the *downloadable family APK* starts with Firebase running,
# rather than the volatile preview build used by the existing smoke job.
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n com.analienx.baby_sleep_tracker/.MainActivity
sleep 5
adb shell pidof com.analienx.baby_sleep_tracker
adb exec-out screencap -p > .e2e/family-persistent-startup.png
adb shell am force-stop com.analienx.baby_sleep_tracker

# The official Flutter integration_test harness installs its own instrumented
# app using the same persistent Firebase compile-time define.
test_status=0
flutter test integration_test/family_emulator_test.dart \
  -d emulator-5554 --no-pub \
  --dart-define=USE_FAMILY_EMULATOR=true \
  --dart-define=FIREBASE_EMULATOR_HOST="${DEVICE_HOST:-10.0.2.2}" \
  -r expanded || test_status=$?

adb exec-out screencap -p > .e2e/family-e2e.png || true
# Redacted-by-selection: error-only Flutter/Firebase Android logs from a
# demo-project emulator. Retain even if the widget test fails.
adb logcat -d -v time -s flutter:E FirebaseAuth:E FirebaseFunctions:E \
  > .e2e/android-errors.log || true
exit "$test_status"
