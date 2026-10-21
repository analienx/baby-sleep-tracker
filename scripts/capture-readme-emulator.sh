#!/usr/bin/env bash
# Real Android emulator screenshots with the actual bundled app font.
# QA-only memory preview: no account, child records, Firebase project or secrets.
set -euo pipefail

OUT="${1:-e2e-evidence/ui}"
PKG="com.analienx.baby_sleep_tracker"
COMPONENT="$PKG/.MainActivity"
mkdir -p "$OUT"

adb wait-for-device
adb shell cmd uimode night no >/dev/null
flutter build apk --debug --no-pub >/dev/null
adb install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null

resolution="$(adb shell wm size | tr -d '\r' | sed -n 's/^Physical size: //p')"
IFS=x read -r WIDTH HEIGHT <<< "$resolution"
[[ "$WIDTH" =~ ^[0-9]+$ && "$HEIGHT" =~ ^[0-9]+$ ]] || { echo "Invalid emulator dimensions" >&2; exit 1; }
x_today=$((WIDTH / 6))
x_trends=$((WIDTH * 5 / 6))
x_settings=$((WIDTH * 9 / 10))
y_navigation=$((HEIGHT - 185))
y_settings=$((HEIGHT / 10))

open_app() {
  adb shell am force-stop "$PKG" || true
  adb shell am start -W -n "$COMPONENT" >/dev/null
  sleep 5
  adb shell dumpsys activity activities | grep -q "$PKG" || { echo "Little Rest not running" >&2; exit 1; }
}

capture() {
  local name="$1" remote="/sdcard/Download/little-rest-readme-$1.png"
  sleep 2
  # A launcher crash, OS permissions dialog, or another focused app is NOT a
  # product screenshot. Fail closed instead of uploading false evidence.
  local focus
  focus="$(adb shell dumpsys window | grep mCurrentFocus | head -1 || true)"
  if [[ "$focus" != *"$PKG"* ]]; then
    echo "Screenshot refused: Little Rest is not the focused window: $focus" >&2
    return 1
  fi
  adb shell screencap -p "$remote"
  adb pull "$remote" "$OUT/$name.png" >/dev/null
  adb shell rm -f "$remote"
  local bytes
  bytes="$(wc -c < "$OUT/$name.png")"
  if (( bytes < 22000 )); then
    echo "Screenshot $name suspiciously small: $bytes bytes" >&2
    exit 1
  fi
  file "$OUT/$name.png"
}

open_app
capture today-light
adb shell input tap "$x_trends" "$y_navigation"
capture trends-light
adb shell input tap "$x_today" "$y_navigation"
adb shell input tap "$x_settings" "$y_settings"
capture settings-light

adb shell cmd uimode night yes >/dev/null
open_app
capture today-dark
echo "Captured four true app screenshots (empty-state preview, no child data)."
