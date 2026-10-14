#!/usr/bin/env python3
"""Writes export_presets.cfg from the preset table below (FND-03).

Run from anywhere: python3 tools/build/gen_export_presets.py
Edit the table here, not the generated file, so the nine presets stay consistent.
"""
from pathlib import Path

GAME = Path(__file__).resolve().parents[2]

# GUT is a development tool and ships in no build.
COMMON_EXCLUDE = ["tests/*", "tools/*", "addons/gut/*", ".gutconfig.json"]
# Cell data, templates and the material table are server-only (GEN-01, Gameplay §5.10).
CLIENT_EXCLUDE = ["server/*", "data/maps/*", "data/templates/*", "data/world/*"] + COMMON_EXCLUDE
SERVER_EXCLUDE = ["client/*", "data/text/*"] + COMMON_EXCLUDE  # data/text: client-only text (SND-10's notice)
RELEASE_EXCLUDE = ["*/debug/*"]


def tuning_server_files():
    """Client packs ship data/tuning/_client.json only, never the domain files (FND-05)."""
    tuning = GAME / "data" / "tuning"
    names = sorted(p.name for p in tuning.glob("*.json") if p.name != "_client.json")
    return [f"data/tuning/{n}" for n in names] + ["data/tuning/profiles/*"]

# name, platform, role, flavour, extra tags
PRESETS = [
    ("windows-client-qa", "windows", "client", "qa", []),
    ("windows-client-release", "windows", "client", "release", []),
    ("linux-client-qa", "linux", "client", "qa", []),
    ("linux-client-release", "linux", "client", "release", []),
    ("windows-server-qa", "windows", "server", "qa", []),
    ("windows-server-release", "windows", "server", "release", []),
    ("linux-server-qa", "linux", "server", "qa", []),
    ("linux-server-release", "linux", "server", "release", []),
    ("windows-client-killtest", "windows", "client", "qa", ["lb_killtest"]),
]
# Four targets x {qa, release}, plus QA-01's kill-test client: nine presets.
# Only the Windows client and server ship to players; linux-client-* serve CI bots and
# developers, and linux-server-* the fleet image (STM-09).

EXE = {
    ("windows", "client"): "lampblack.exe",
    ("windows", "server"): "lampblack_server.exe",
    ("linux", "client"): "lampblack.x86_64",
    ("linux", "server"): "lampblack_server.x86_64",
}


def preset_block(index, name, platform, role, flavour, extra):
    tags = [f"lb_{role}", f"lb_{flavour}"] + extra
    exclude = (CLIENT_EXCLUDE + tuning_server_files() if role == "client" else SERVER_EXCLUDE)
    if flavour == "release":
        exclude = exclude + RELEASE_EXCLUDE
    server = role == "server"
    lines = [
        f"[preset.{index}]",
        "",
        f'name="{name}"',
        f'platform="{"Windows Desktop" if platform == "windows" else "Linux"}"',
        "runnable=false",
        "advanced_options=true",
        f"dedicated_server={'true' if server else 'false'}",
        f'custom_features="{",".join(tags)}"',
    ]
    if server:
        lines += ['export_filter="customized"', 'customized_files={', '"res://": "strip"', "}"]
    else:
        lines += ['export_filter="all_resources"']
    lines += [
        # SND-13's character voices (.lbv) are raw files the client reads, not imported resources.
        f'include_filter="{"*.json, *.lbv" if role == "client" else "*.json"}"',
        f'exclude_filter="{", ".join(exclude)}"',
        f'export_path="build/{name}/{EXE[(platform, role)]}"',
        "patches=PackedStringArray()",
        'encryption_include_filters=""',
        'encryption_exclude_filters=""',
        "seed=0",
        "encrypt_pck=false",
        "encrypt_directory=false",
        "script_export_mode=2",
        "",
        f"[preset.{index}.options]",
        "",
        'custom_template/debug=""',
        'custom_template/release=""',
        "binary_format/embed_pck=false",
        'binary_format/architecture="x86_64"',
    ]
    if platform == "windows":
        lines += [
            # A server started by the host's client opens no console window (STM-04).
            f"debug/export_console_wrapper={'0' if server else '1'}",
            "codesign/enable=false",
            # Editing the exe's icon and version needs rcedit; the placeholder icon is
            # enough until STM-13.
            "application/modify_resources=false",
            "application/export_angle=0",
            "application/export_d3d12=0",
        ]
    else:
        lines += ["debug/export_console_wrapper=0"]
    lines += [
        "texture_format/s3tc_bptc=true",
        "texture_format/etc2_astc=false",
        "",
    ]
    return "\n".join(lines)


def main():
    blocks = [preset_block(i, *p) for i, p in enumerate(PRESETS)]
    (GAME / "export_presets.cfg").write_text("\n".join(blocks))
    print(f"wrote {len(blocks)} presets to {GAME / 'export_presets.cfg'}")


if __name__ == "__main__":
    main()
