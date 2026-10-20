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
if ! flutter test integration_test/family_emulator_test.dart \
  -d emulator-5554 --no-pub \
  --dart-define=USE_FAMILY_EMULATOR=true \
  -r expanded; then
  adb exec-out screencap -p > .e2e/family-e2e-failure.png || true
  adb logcat -d -t 400 > .e2e/android-logcat-failure.txt || true
  exit 1
fi

adb exec-out screencap -p > .e2e/family-e2e.png
