#!/usr/bin/env bash
# Ashfall lint gate. Must pass before any phase is called done.
#
#   ./scripts/lint.sh          format check + lint + engine parse check
#   ./scripts/lint.sh --fix    rewrite files with gdformat, then lint + parse check
#
# Requires: gdtoolkit 4 (pip install "gdtoolkit==4.*") and the Godot 4.5 binary.
# On Windows, run this from Git Bash. Set GODOT to your binary if it is not on PATH:
#   GODOT="/c/Program Files/Godot/Godot_v4.5-stable_win64.exe" ./scripts/lint.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

# gdtoolkit installs into the per-user Python scripts dir, which is not on PATH under Git Bash.
for d in "$APPDATA/Python"/Python*/Scripts "$HOME/.local/bin"; do
  [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$PATH:$d" ;; esac
done
export PATH

# Find Godot without making every caller export GODOT. An explicit GODOT always wins.
find_godot() {
  [ -n "${GODOT:-}" ] && { printf '%s' "$GODOT"; return; }
  command -v godot >/dev/null 2>&1 && { printf 'godot'; return; }
  local c
  for c in \
    "$LOCALAPPDATA/Microsoft/WinGet/Packages"/GodotEngine.GodotEngine_*/Godot_v*_win64.exe \
    "$LOCALAPPDATA/Microsoft/WinGet/Links/godot.exe" \
    "/c/Program Files/Godot"/Godot_v*.exe \
    "/c/Program Files/Godot/godot.exe"
  do
    # Skip the console variant: it detaches and returns before the check completes.
    case "$c" in *console*) continue ;; esac
    [ -x "$c" ] && { printf '%s' "$c"; return; }
  done
  printf 'godot'
}
GODOT="$(find_godot)"

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; OFF=$'\033[0m'
FAILED=0

step() { printf '\n%s==> %s%s\n' "$YEL" "$1" "$OFF"; }
fail() { printf '%s[FAIL]%s %s\n' "$RED" "$OFF" "$1"; FAILED=1; }
ok()   { printf '%s[ OK ]%s %s\n' "$GRN" "$OFF" "$1"; }
skip() { printf '%s[SKIP]%s %s\n' "$YEL" "$OFF" "$1"; }

# Collect project scripts. Excludes engine cache and the Android build template.
mapfile -t GD_FILES < <(
  find . -name '*.gd' \
    -not -path './.godot/*' \
    -not -path './android/build/*' \
    -not -path './addons/*' \
    | sort
)

if [ "${#GD_FILES[@]}" -eq 0 ]; then
  skip "no .gd files yet"
else
  printf 'linting %d script(s)\n' "${#GD_FILES[@]}"
fi

# ---------------------------------------------------------------- gdformat
step "gdformat"
if ! command -v gdformat >/dev/null 2>&1; then
  skip "gdformat not found — pip install \"gdtoolkit==4.*\""
elif [ "${#GD_FILES[@]}" -eq 0 ]; then
  skip "nothing to format"
elif [ "$FIX" -eq 1 ]; then
  gdformat "${GD_FILES[@]}" && ok "reformatted" || fail "gdformat errored"
else
  gdformat --check "${GD_FILES[@]}" && ok "formatting clean" \
    || fail "formatting drift — run ./scripts/lint.sh --fix"
fi

# ------------------------------------------------------------------ gdlint
step "gdlint"
if ! command -v gdlint >/dev/null 2>&1; then
  skip "gdlint not found — pip install \"gdtoolkit==4.*\""
elif [ "${#GD_FILES[@]}" -eq 0 ]; then
  skip "nothing to lint"
else
  gdlint "${GD_FILES[@]}" && ok "lint clean" || fail "gdlint reported problems"
fi

# --------------------------------------------------- godot project validation
# A full project import, not a per-file --check-only pass.
#
# --check-only --script compiles one file with no project context, so every autoload reference
# ("InputRouter", "QualityManager") reads as an undefined identifier and the gate drowns in false
# positives. Importing validates each script the way the game actually loads it: autoloads
# registered, global classes resolved, scenes instantiated. It is also what caught the real Phase 1
# breakages -- a shadowed parameter, a class_name colliding with a native type, and unresolved node
# path exports.
step "godot project validation"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  skip "godot binary not found — set GODOT=/path/to/Godot_v4.5-stable_*"
else
  out="$("$GODOT" --headless --path . --import 2>&1 | tr -d '\r')"
  if printf '%s' "$out" | grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|ERROR:'; then
    printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|ERROR:|  at:'
    fail "engine reported script or scene errors"
  else
    ok "project imports clean (${#GD_FILES[@]} scripts, autoloads resolved)"
  fi
fi

# --------------------------------------------------- orphaned scripts
#
# A script nothing can reach. The unit suite CANNOT catch this by construction -- a well-tested
# orphan passes every test it has -- and it has bitten twice: the whole Phase 7 UI wired into no
# scene, and Bloodstain with no scene to instantiate, which left the Souls death loop unclosable.
step "orphaned scripts"
if ! command -v python >/dev/null 2>&1; then
  skip "python not found"
else
  if out="$(python tools/find_orphans.py 2>&1)"; then
    ok "$(printf '%s' "$out" | tail -1)"
  else
    printf '%s
' "$out"
    fail "unreachable scripts — wire, reference, delete, or justify in tools/find_orphans.py"
  fi
fi

# ------------------------------------------------------------------ verdict
printf '\n'
if [ "$FAILED" -ne 0 ]; then
  printf '%slint gate FAILED%s\n' "$RED" "$OFF"
  exit 1
fi
printf '%slint gate passed%s\n' "$GRN" "$OFF"
