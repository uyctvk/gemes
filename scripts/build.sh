#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
mkdir -p build/windows build/linux
touch build/.gdignore
bash scripts/godot.sh --headless --export-release "Windows Desktop" build/windows/LivingWorld.exe
bash scripts/godot.sh --headless --export-release "Linux Desktop" build/linux/LivingWorld.x86_64
cp game/assets/FONT-LICENSE.txt build/windows/FONT-LICENSE.txt
cp game/assets/FONT-LICENSE.txt build/linux/FONT-LICENSE.txt
cp docs/PLAY.md build/windows/PLAY.txt
cp docs/PLAY.md build/linux/PLAY.txt
for platform in windows linux; do
  cp docs/licenses/GODOT-LICENSE.txt "build/$platform/GODOT-LICENSE.txt"
  cp docs/licenses/GODOT-THIRD-PARTY.txt "build/$platform/GODOT-THIRD-PARTY.txt"
done
python3 - <<'PY'
from pathlib import Path
import hashlib, zipfile
root=Path('build')
for platform in ['windows','linux']:
    archive=root/f'LivingWorld-0.1.0-{platform}-x86_64.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted((root/platform).iterdir()):
            z.write(p,arcname=p.name)
    print(archive,archive.stat().st_size,'bytes')
(root/'SHA256SUMS.txt').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n'
    for p in sorted(root.glob('*.zip'))))
PY
