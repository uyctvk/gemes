#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
RUN_DIRECTORY="$(mktemp -d /tmp/living-world-check.XXXXXX)"
export LIVING_WORLD_TEST_DIR="$RUN_DIRECTORY/domain"
run_checked() {
  local log="$1"
  shift
  "$@" >"$log" 2>&1 || { cat "$log"; return 1; }
  cat "$log"
  if rg -q 'SCRIPT ERROR|Parse Error|^ERROR:|FAIL ' "$log"; then return 1; fi
}
run_checked "$RUN_DIRECTORY/import.log" bash scripts/godot.sh --headless --editor --import --quit
run_checked "$RUN_DIRECTORY/domain.log" bash scripts/godot.sh --headless --script tests/run.gd
rg -q 'RESULT: [1-9][0-9]* passed; 0 failed;' "$RUN_DIRECTORY/domain.log"
run_checked "$RUN_DIRECTORY/scene.log" timeout 60 bash scripts/godot.sh --headless -- --smoke --save-dir="$RUN_DIRECTORY/scene"
rg -q 'SCENE_SMOKE: PASS' "$RUN_DIRECTORY/scene.log"
rg -q 'PHYSICS_SMOKE: PASS' "$RUN_DIRECTORY/scene.log"
printf 'Validation logs: %s\n' "$RUN_DIRECTORY"
