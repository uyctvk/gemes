#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_CACHE_HOME="${PROJECT_ROOT}/.local/cache"
export XDG_CONFIG_HOME="${PROJECT_ROOT}/.local/config"
export XDG_DATA_HOME="${PROJECT_ROOT}/.local/data"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
GODOT_EXECUTABLE="${GODOT_BIN:-godot}"
if [[ -z "${GODOT_BIN:-}" && -x "$PROJECT_ROOT/.local/tools/godot" ]]; then
  GODOT_EXECUTABLE="$PROJECT_ROOT/.local/tools/godot"
fi
exec "$GODOT_EXECUTABLE" --path "$PROJECT_ROOT" "$@"
