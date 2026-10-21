#!/usr/bin/env python3
"""Install/refresh the exact Linux editor and optional PC export templates.

Only .local is mutated. Downloads use TLS and pinned official SHA-512 checksums.
No pip/npm packages, API keys, Steam SDK, or persistent services are required.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.6.3"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/"
ARTIFACTS = {
    "editor": ("Godot_v4.6.3-stable_linux.x86_64.zip", "a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c"),
    "exports": ("Godot_v4.6.3-stable_export_templates.tpz", "da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68"),
}


def digest(path: Path) -> str:
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha512").hexdigest()


def artifact(kind: str) -> Path:
    name, expected = ARTIFACTS[kind]
    cache = ROOT / ".local/downloads"
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / name
    if path.exists() and digest(path) == expected:
        print(f"Verified cached {name}", flush=True)
        return path
    temporary = path.with_suffix(path.suffix + ".partial")
    print(f"Downloading {name}" + (" (1.26 GB)" if kind == "exports" else ""), flush=True)
    with urllib.request.urlopen(BASE + name, timeout=180) as source, temporary.open("wb") as out:
        shutil.copyfileobj(source, out, 8 * 1024 * 1024)
    if digest(temporary) != expected:
        temporary.unlink()
        raise RuntimeError(f"SHA-512 mismatch for {name}; artifact rejected")
    temporary.replace(path)
    print("SHA-512 verified.", flush=True)
    return path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--exports", action="store_true", help="Install Windows/Linux release export templates")
    args = parser.parse_args()
    for key, suffix in [("XDG_CACHE_HOME", "cache"), ("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data")]:
        directory = ROOT / ".local" / suffix
        directory.mkdir(parents=True, exist_ok=True)
        os.environ[key] = str(directory)
    executable = os.environ.get("GODOT_BIN") or shutil.which("godot")
    local = ROOT / ".local/tools/godot"
    if local.exists():
        executable = str(local)
    version = ""
    if executable:
        result = subprocess.run([executable, "--version"], capture_output=True, text=True, check=True)
        version = result.stdout.strip()
    if not version.startswith(VERSION + ".stable"):
        if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
            raise SystemExit("Install Godot 4.6.3 for this OS, then set GODOT_BIN to its executable.")
        local.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(artifact("editor")) as z:
            with z.open("Godot_v4.6.3-stable_linux.x86_64") as source, local.open("wb") as out:
                shutil.copyfileobj(source, out)
        local.chmod(0o755)
        executable = str(local)
    print(f"Godot editor: {executable}", flush=True)
    if args.exports:
        destination = ROOT / ".local/data/godot/export_templates/4.6.3.stable"
        destination.mkdir(parents=True, exist_ok=True)
        # Re-extract from the verified archive; installation is repeatable.
        with zipfile.ZipFile(artifact("exports")) as z:
            for name in ["linux_release.x86_64", "windows_release_x86_64.exe", "version.txt"]:
                with z.open("templates/" + name) as source, (destination / name).open("wb") as out:
                    shutil.copyfileobj(source, out)
        (destination / "linux_release.x86_64").chmod(0o755)
        print("Windows/Linux export templates installed.", flush=True)
    subprocess.run([executable, "--headless", "--path", str(ROOT), "--editor", "--import", "--quit"], check=True)


if __name__ == "__main__":
    main()
