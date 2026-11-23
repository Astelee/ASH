#!/usr/bin/env bash
# Ashfall Android build. AAB for Play, APK for sideload.
#
#   ./scripts/build.sh apk            debug APK
#   ./scripts/build.sh apk --install  debug APK, then adb install -r
#   ./scripts/build.sh aab            release AAB, then verify 16 KB alignment
#
# Signing comes from the environment, never from a committed file:
#   ASHFALL_KEYSTORE, ASHFALL_KEYSTORE_USER, ASHFALL_KEYSTORE_PASS
#
# Losing that keystore means you can never update the app on Play. Back it up off this machine.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; OFF=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$YEL" "$1" "$OFF"; }
fail() { printf '%s[FAIL]%s %s\n' "$RED" "$OFF" "$1"; exit 1; }
ok()   { printf '%s[ OK ]%s %s\n' "$GRN" "$OFF" "$1"; }

find_godot() {
  [ -n "${GODOT:-}" ] && { printf '%s' "$GODOT"; return; }
  command -v godot >/dev/null 2>&1 && { printf 'godot'; return; }
  local c
  for c in "$LOCALAPPDATA/Microsoft/WinGet/Packages"/GodotEngine.GodotEngine_*/Godot_v*_win64.exe; do
    case "$c" in *console*) continue ;; esac
    [ -x "$c" ] && { printf '%s' "$c"; return; }
  done
  printf 'godot'
}
GODOT="$(find_godot)"

TARGET="${1:-apk}"
INSTALL=0
[ "${2:-}" = "--install" ] && INSTALL=1

mkdir -p export

# The gates run before every build, without exception. A build that ships a red suite is worse than
# no build, because it looks like progress.
step "gates"
./scripts/lint.sh >/dev/null 2>&1 || fail "lint gate is red — fix it before building"
ok "lint"
SKIP_SHADER_CHECK=1 ./scripts/test.sh >/dev/null 2>&1 || fail "test gate is red — fix it before building"
ok "tests"

case "$TARGET" in
  apk)
    step "export debug APK"
    "$GODOT" --headless --path . --export-debug "Android APK" export/ashfall.apk \
      || fail "export failed — is the Android build template installed?"
    ok "export/ashfall.apk"

    if [ "$INSTALL" -eq 1 ]; then
      step "adb install"
      command -v adb >/dev/null 2>&1 || fail "adb not on PATH"
      adb install -r export/ashfall.apk || fail "install failed"
      ok "installed"
    fi
    ;;

  aab)
    [ -n "${ASHFALL_KEYSTORE:-}" ] || fail "ASHFALL_KEYSTORE is not set"
    [ -f "$ASHFALL_KEYSTORE" ] || fail "keystore not found at $ASHFALL_KEYSTORE"

    step "export release AAB"
    "$GODOT" --headless --path . --export-release "Android AAB" export/ashfall.aab \
      || fail "export failed"
    ok "export/ashfall.aab"

    # Required for Play submission. Devices with 16 KB memory pages reject 4 KB-aligned native
    # libraries, and a Gradle plugin or an old NDK anywhere in the chain can silently undo Godot's
    # alignment. Checked on every release build rather than trusted.
    step "16 KB page alignment"
    rm -rf export/_libcheck && mkdir -p export/_libcheck
    unzip -qo export/ashfall.aab 'base/lib/*' -d export/_libcheck 2>/dev/null \
      || unzip -qo export/ashfall.aab 'lib/*' -d export/_libcheck 2>/dev/null \
      || fail "no native libs found in the AAB"

    READELF="$(command -v llvm-readelf || command -v readelf || true)"
    [ -n "$READELF" ] || fail "need llvm-readelf or readelf on PATH"

    MISALIGNED=0
    while IFS= read -r lib; do
      if "$READELF" -lW "$lib" 2>/dev/null | awk '/LOAD/ { print $NF }' | grep -qv '0x4000'; then
        printf '%s  %s\n' "$RED[misaligned]$OFF" "$lib"
        MISALIGNED=1
      fi
    done < <(find export/_libcheck -name '*.so')

    [ "$MISALIGNED" -eq 0 ] || fail "native libs are not 16 KB aligned — Play will reject this upload"
    ok "every LOAD segment is 0x4000 aligned"
    rm -rf export/_libcheck
    ;;

  *)
    fail "unknown target '$TARGET' (expected apk or aab)"
    ;;
esac

printf '\n%sbuild complete%s\n' "$GRN" "$OFF"
