#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIRECTORY="$(mktemp -d /tmp/living-world-visual.XXXXXX)"
XORG_PID=""
cleanup() {
  if [[ -n "$XORG_PID" ]]; then kill "$XORG_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT
if [[ -z "${DISPLAY:-}" ]]; then
  XORG_BINARY=/usr/lib/xorg/Xorg
  [[ -x "$XORG_BINARY" ]] || { echo 'Visual check needs Xorg dummy driver or an existing DISPLAY.'; exit 1; }
  cat > "$RUN_DIRECTORY/xorg.conf" <<'EOF'
Section "Device"
  Identifier "Dummy"
  Driver "dummy"
  VideoRam 256000
EndSection
Section "Monitor"
  Identifier "Monitor"
  HorizSync 5.0 - 1000.0
  VertRefresh 5.0 - 200.0
  Modeline "1440x900" 106.50 1440 1520 1672 1904 900 903 909 934 -hsync +vsync
EndSection
Section "Screen"
  Identifier "Screen"
  Device "Dummy"
  Monitor "Monitor"
  DefaultDepth 24
  SubSection "Display"
    Depth 24
    Modes "1440x900"
  EndSubSection
EndSection
Section "ServerFlags"
  Option "AutoAddDevices" "false"
EndSection
EOF
  for number in {92..99}; do
    if [[ ! -e "/tmp/.X${number}-lock" ]]; then export DISPLAY=":${number}"; break; fi
  done
  [[ -n "${DISPLAY:-}" ]] || { echo 'No unused test display.'; exit 1; }
  "$XORG_BINARY" "$DISPLAY" -noreset -nolisten tcp -config "$RUN_DIRECTORY/xorg.conf" -logfile "$RUN_DIRECTORY/xorg.log" >"$RUN_DIRECTORY/xorg-start.log" 2>&1 &
  XORG_PID=$!
  for attempt in {1..30}; do
    if xdpyinfo >/dev/null 2>&1; then break; fi
    sleep 0.2
  done
  xdpyinfo >/dev/null
fi
export LIBGL_ALWAYS_SOFTWARE=1
cd "$PROJECT_ROOT"
if [[ -n "${LW_VISUAL_EXECUTABLE:-}" ]]; then
  export XDG_CACHE_HOME="$RUN_DIRECTORY/cache" XDG_CONFIG_HOME="$RUN_DIRECTORY/config" XDG_DATA_HOME="$RUN_DIRECTORY/data"
  "$LW_VISUAL_EXECUTABLE" --audio-driver Dummy -- --capture --save-dir="$RUN_DIRECTORY/save" >"$RUN_DIRECTORY/game.log" 2>&1
else
  bash scripts/godot.sh --audio-driver Dummy -- --capture --save-dir="$RUN_DIRECTORY/save" >"$RUN_DIRECTORY/game.log" 2>&1
fi
cat "$RUN_DIRECTORY/game.log"
if rg -q 'SCRIPT ERROR|^ERROR:' "$RUN_DIRECTORY/game.log"; then exit 1; fi
mkdir -p build/screenshots
touch build/.gdignore
for name in title village market character attack; do
  test -s "/tmp/living-world-$name.png"
  cp "/tmp/living-world-$name.png" "build/screenshots/$name.png"
done
printf 'Visual evidence: %s/build/screenshots\n' "$PROJECT_ROOT"
