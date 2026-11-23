#!/usr/bin/env bash
# On-device frame timing for Ashfall.
#
#   ./scripts/perf.sh              capture 120 frames of gfxinfo
#   ./scripts/perf.sh --thermal    20-minute thermal soak, sampling every 30 s
#
# This is the measurement every "unverified on device" note in DEV_LOG.md is waiting for. Nothing in
# the repo can substitute for it: draw calls and triangle counts transfer from desktop, frame time
# and thermal behaviour do not.

set -uo pipefail

PKG="${ASHFALL_PACKAGE:-com.ashfall.game}"
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; OFF=$'\033[0m'

command -v adb >/dev/null 2>&1 || { printf '%sadb not on PATH%s\n' "$RED" "$OFF"; exit 1; }
adb get-state >/dev/null 2>&1 || { printf '%sno device connected%s\n' "$RED" "$OFF"; exit 1; }

printf '%sdevice:%s %s\n' "$YEL" "$OFF" "$(adb shell getprop ro.product.model | tr -d '\r')"
printf '%sSoC:%s    %s\n' "$YEL" "$OFF" "$(adb shell getprop ro.board.platform | tr -d '\r')"
printf '%spackage:%s %s\n\n' "$YEL" "$OFF" "$PKG"

# ------------------------------------------------------------------ frame timing
capture_frames() {
  adb shell dumpsys gfxinfo "$PKG" reset >/dev/null 2>&1
  sleep 4
  local raw
  raw="$(adb shell dumpsys gfxinfo "$PKG" framestats 2>/dev/null | tr -d '\r')"

  printf '%s\n' "$raw" | awk '
    /^---PROFILEDATA---/ { collecting = !collecting; next }
    collecting && /^[0-9]/ {
      split($0, f, ",")
      # Column 2 is INTENDED_VSYNC, column 14 FRAME_COMPLETED. Nanoseconds.
      if (f[14] > 0 && f[2] > 0) {
        ms = (f[14] - f[2]) / 1000000.0
        if (ms > 0 && ms < 500) { total += ms; n++; if (ms > peak) peak = ms; if (ms > 16.6) janky++ }
      }
    }
    END {
      if (n == 0) { print "  no frame data — is the app in the foreground?"; exit }
      printf "  frames sampled  %d\n", n
      printf "  mean frame      %.2f ms\n", total / n
      printf "  worst frame     %.2f ms\n", peak
      printf "  over 16.6 ms    %d  (%.1f%%)\n", janky, (janky * 100.0) / n
    }'
}

if [ "${1:-}" = "--thermal" ]; then
  # Twenty minutes is the Phase 9 acceptance window. Sustained load is where a mid-tier phone
  # throttles, and a game that holds 60 FPS for two minutes and 42 for twenty has not passed.
  printf '%s==> thermal soak, 20 minutes%s\n\n' "$YEL" "$OFF"
  for minute in $(seq 0 30 1170); do
    printf '%s+%02d:%02d%s\n' "$YEL" $((minute / 60)) $((minute % 60)) "$OFF"
    capture_frames
    printf '  battery temp    %s\n\n' \
      "$(adb shell dumpsys battery | awk '/temperature/ { printf "%.1f C", $2 / 10 }')"
    sleep 26
  done
else
  printf '%s==> frame capture%s\n' "$YEL" "$OFF"
  capture_frames
fi

printf '\n%sRecord the result in docs/DEV_LOG.md.%s\n' "$GRN" "$OFF"
printf 'Deeper profiling: simpleperf record -p $(adb shell pidof %s) -g --duration 20\n' "$PKG"
