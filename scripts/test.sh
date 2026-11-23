#!/usr/bin/env bash
# Ashfall test gate. Must pass before any phase is called done.
#
#   ./scripts/test.sh
#
# Runs headless and exits non-zero if any suite fails.
#
#   GUT unit suite       tests/test_*.gd  — pure logic: damage, scheduler, stats
#   MovementCheck.tscn   the movement table from docs/GDD.md §5
#   CombatCheck.tscn     combat wiring and the attack-token cap under live AI
#
# The unit suites prove the maths; the scene checks prove the numbers survive the trip through the
# scene tree. Both are needed — every Phase 1 and Phase 2 bug found so far lived in exactly one of
# those two places and was invisible from the other.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Same discovery as lint.sh: Godot is not on PATH under Git Bash.
find_godot() {
  [ -n "${GODOT:-}" ] && { printf '%s' "$GODOT"; return; }
  command -v godot >/dev/null 2>&1 && { printf 'godot'; return; }
  local c
  for c in \
    "$LOCALAPPDATA/Microsoft/WinGet/Packages"/GodotEngine.GodotEngine_*/Godot_v*_win64.exe \
    "$LOCALAPPDATA/Microsoft/WinGet/Links/godot.exe" \
    "/c/Program Files/Godot"/Godot_v*.exe
  do
    case "$c" in *console*) continue ;; esac
    [ -x "$c" ] && { printf '%s' "$c"; return; }
  done
  printf 'godot'
}
GODOT="$(find_godot)"

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; OFF=$'\033[0m'

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  printf '%s[SKIP]%s godot binary not found — set GODOT=/path/to/Godot_v4.5-stable_*\n' "$YEL" "$OFF"
  exit 1
fi

FAILED=0

# Every invocation is wrapped in `timeout` with stdin closed. Godot under --headless will block
# indefinitely waiting on a console it does not have, and a gate that hangs is worse than one that
# fails: it takes the run down with no output at all.
SUITE_TIMEOUT="${SUITE_TIMEOUT:-180}"

report() {
  local label="$1" status="$2"
  if [ "$status" -eq 124 ]; then
    printf '%s[FAIL]%s %s timed out after %ss\n' "$RED" "$OFF" "$label" "$SUITE_TIMEOUT"
    FAILED=1
  elif [ "$status" -ne 0 ]; then
    printf '%s[FAIL]%s %s exited %d\n' "$RED" "$OFF" "$label" "$status"
    FAILED=1
  else
    printf '%s[ OK ]%s %s\n' "$GRN" "$OFF" "$label"
  fi
}

# ------------------------------------------------------------------ unit suite
printf '\n%s==> GUT unit suite%s\n' "$YEL" "$OFF"
out="$(timeout "$SUITE_TIMEOUT" "$GODOT" --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit \
  </dev/null 2>&1 | tr -d '\r')"
status=$?
printf '%s\n' "$out" | grep -E 'Scripts|Tests|Passing|Asserts|failing|All tests|ERROR'
if printf '%s' "$out" | grep -q 'All tests passed'; then
  report "GUT unit suite" "$status"
else
  report "GUT unit suite" 1
fi

# ---------------------------------------------------------------- scene checks
for scene in res://tests/MovementCheck.tscn res://tests/CombatCheck.tscn; do
  printf '\n%s==> %s%s\n' "$YEL" "$scene" "$OFF"
  if [ ! -f "${scene#res://}" ]; then
    printf '%s[SKIP]%s does not exist yet\n' "$YEL" "$OFF"
    continue
  fi
  out="$(timeout "$SUITE_TIMEOUT" "$GODOT" --headless --path . "$scene" </dev/null 2>&1 | tr -d '\r')"
  status=$?
  printf '%s\n' "$out" | grep -E '^\s+(PASS|FAIL)|^--- '
  report "$scene" "$status"
done

# --------------------------------------------------------------- budget check
# Real renderer again, for the same reason: the headless dummy rasteriser reports zero for every
# render monitor, so a headless budget check would happily pass a scene with ten thousand draw calls.
printf '
%s==> budget check (real renderer)%s
' "$YEL" "$OFF"
if [ "${SKIP_SHADER_CHECK:-0}" = "1" ]; then
  printf '%s[SKIP]%s SKIP_SHADER_CHECK=1
' "$YEL" "$OFF"
else
  for budget_scene in res://tests/BudgetVillage.tscn res://tests/BudgetArena.tscn; do
    out="$(timeout "$SUITE_TIMEOUT" "$GODOT" --path . "$budget_scene" </dev/null 2>&1 | tr -d '')"
    status=$?
    printf '%s
' "$out" | grep -E '^  (PASS|FAIL|INFO)|^--- ' || true
    report "$budget_scene" "$status"
  done
fi

# ------------------------------------------------------------- shader compile
# Deliberately NOT --headless. The dummy rasteriser skips shader compilation entirely, so a headless
# run proves only that the .gdshader files parse as resources -- it cannot catch a removed builtin or
# a type error inside a light() function. This step opens a real context and draws every shader once.
#
# It has already earned its place: it caught DEPTH_TEXTURE being removed in Godot 4.7, which the
# headless suite reported as a clean pass.
#
# Set SKIP_SHADER_CHECK=1 on a machine with no display.
printf '\n%s==> shader compile (real renderer)%s\n' "$YEL" "$OFF"
if [ "${SKIP_SHADER_CHECK:-0}" = "1" ]; then
  printf '%s[SKIP]%s SKIP_SHADER_CHECK=1\n' "$YEL" "$OFF"
else
  out="$(timeout "$SUITE_TIMEOUT" "$GODOT" --path . res://tests/ShaderCompileCheck.tscn </dev/null 2>&1 | tr -d '\r')"
  status=$?
  printf '%s\n' "$out" | grep -E '^--- ' || true
  if printf '%s' "$out" | grep -qE 'SHADER ERROR|Shader compilation failed'; then
    printf '%s\n' "$out" | grep -E 'SHADER ERROR|Shader compilation failed|gdshader'
    printf '%s[FAIL]%s shaders did not compile\n' "$RED" "$OFF"
    FAILED=1
  else
    report "shader compile" "$status"
  fi
fi

# ---------------------------------------------------------------------- verdict
printf '\n'
if [ "$FAILED" -ne 0 ]; then
  printf '%stest gate FAILED%s\n' "$RED" "$OFF"
  exit 1
fi
printf '%stest gate passed%s\n' "$GRN" "$OFF"
