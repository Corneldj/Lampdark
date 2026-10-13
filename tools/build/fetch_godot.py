#!/usr/bin/env python3
"""FND-04: fetches the pinned Godot editor and export templates named in versions.json, verifies
each download's SHA-512 against it, and installs them. A mismatch, or a file versions.json does not
name, fails the run before anything is unpacked.

Usage:
  fetch_godot.py --platform linux|windows --dest <dir> [--templates] [--cache <dir>] [--github-env]
      Downloads (or reuses from --cache) the editor zip, verifies it and unpacks it into <dir>.
      Prints the editor's path; with --github-env also appends GODOT=<path> to $GITHUB_ENV.
      --templates also fetches the templates .tpz and installs this platform's desktop templates
      (x86_64, debug and release) where the editor looks for them.
  fetch_godot.py --verify <file> [<file> ...]
      Verifies files already on disk against versions.json (tools/build/check_versions.sh).
"""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import stat
import sys
import urllib.request
import zipfile

GAME_DIR = pathlib.Path(__file__).resolve().parents[2]
RELEASES = "https://github.com/godotengine/godot-builds/releases/download"


def engine() -> dict:
    return json.loads((GAME_DIR / "versions.json").read_text(encoding="utf-8"))["engine"]


def sha512(path: pathlib.Path) -> str:
    h = hashlib.sha512()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def verify(path: pathlib.Path) -> bool:
    want = engine()["sha512"].get(path.name)
    if want is None:
        print(f"fetch_godot: {path.name} is not named in versions.json", file=sys.stderr)
        return False
    got = sha512(path)
    if got != want:
        print(f"fetch_godot: checksum mismatch for {path.name}\n  versions.json {want}\n  downloaded    {got}", file=sys.stderr)
        return False
    print(f"ok   {path.name} matches versions.json")
    return True


def fetch(name: str, cache: pathlib.Path) -> pathlib.Path:
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / name
    if not path.exists():
        url = f"{RELEASES}/{engine()['version']}/{name}"
        print(f"fetch_godot: downloading {url}")
        part = path.with_name(name + ".part")
        with urllib.request.urlopen(url, timeout=120) as r, open(part, "wb") as out:
            shutil.copyfileobj(r, out, 1 << 20)
        part.replace(path)
    if not verify(path):
        path.unlink()
        sys.exit(1)
    return path


def templates_dir() -> pathlib.Path:
    e = engine()
    folder = f"{e['major']}.{e['minor']}.{e['patch']}.{e['status']}"
    if sys.platform == "win32":
        return pathlib.Path(os.environ["APPDATA"]) / "Godot" / "export_templates" / folder
    base = os.environ.get("XDG_DATA_HOME") or str(pathlib.Path.home() / ".local" / "share")
    return pathlib.Path(base) / "godot" / "export_templates" / folder


def install_templates(tpz: pathlib.Path) -> None:
    # Every desktop preset exports from Linux (FND-04), so both platforms' x86_64 templates.
    wanted = {"version.txt", "linux_debug.x86_64", "linux_release.x86_64", "windows_debug_x86_64.exe",
              "windows_debug_x86_64_console.exe", "windows_release_x86_64.exe", "windows_release_x86_64_console.exe"}
    dest = templates_dir()
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(tpz) as z:
        for info in z.infolist():
            name = pathlib.PurePosixPath(info.filename).name
            if name in wanted:
                with z.open(info) as src, open(dest / name, "wb") as out:
                    shutil.copyfileobj(src, out, 1 << 20)
                wanted.discard(name)
    if wanted:
        print(f"fetch_godot: the templates lack {sorted(wanted)}", file=sys.stderr)
        sys.exit(1)
    for f in dest.iterdir():
        if f.name.startswith("linux_"):
            f.chmod(f.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"fetch_godot: templates installed in {dest}")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--platform", choices=["linux", "windows"])
    p.add_argument("--dest")
    p.add_argument("--templates", action="store_true")
    p.add_argument("--cache", default=str(pathlib.Path.home() / ".cache" / "lampblack" / "godot"))
    p.add_argument("--github-env", action="store_true")
    p.add_argument("--verify", nargs="+")
    a = p.parse_args()
    if a.verify:
        return 0 if all([verify(pathlib.Path(f)) for f in a.verify]) else 1
    if not a.platform or not a.dest:
        p.error("--platform and --dest are required")
    version = engine()["version"]
    cache = pathlib.Path(a.cache)
    if a.platform == "linux":
        archive, binary = f"Godot_v{version}_linux.x86_64.zip", f"Godot_v{version}_linux.x86_64"
    else:
        archive, binary = f"Godot_v{version}_win64.exe.zip", f"Godot_v{version}_win64_console.exe"
    zipped = fetch(archive, cache)
    dest = pathlib.Path(a.dest).resolve()
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zipped) as z:
        z.extractall(dest)
    editor = dest / binary
    if not editor.exists():
        print(f"fetch_godot: {archive} holds no {binary}", file=sys.stderr)
        return 1
    editor.chmod(editor.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    if a.templates:
        marker = templates_dir() / "version.txt"
        want = f"{engine()['major']}.{engine()['minor']}.{engine()['patch']}.{engine()['status']}"
        if marker.exists() and marker.read_text(encoding="utf-8").strip() == want:
            # CI restores this folder from a cache keyed by versions.json, filled by a verified run.
            print(f"fetch_godot: templates {want} already installed in {templates_dir()}")
        else:
            tpz = fetch(f"Godot_v{version}_export_templates.tpz", cache)
            install_templates(tpz)
            tpz.unlink()  # 1.3 GB; the installed templates are what CI caches
    print(editor)
    if a.github_env and os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env:
            env.write(f"GODOT={editor}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
