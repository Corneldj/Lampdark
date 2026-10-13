# LAMPBLACK — game project

The Godot project for LAMPBLACK. One project produces the client and the headless server (GDD §15.1). Design lives in `Docs/Design/`, tickets in `Implementation/Tickets/`.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Godot (standard, not .NET) | **4.7.2-stable** | [Download](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable). Verify the SHA-512 against `versions.json`. |
| Godot export templates | 4.7.2-stable | Needed from FND-03 on. |
| Git | 2.40+ | |
| Git LFS | 3.x | Binary assets (`*.png *.wav *.ogg *.ttf *.otf`) go through LFS. Run `git lfs install` once. |
| GUT | 9.7.1 | Vendored in `addons/gut/`. Nothing to install. |

| GCC (C++17) | 13+ (tested 16.2) | Linux native builds. Fedora: `gcc-c++ libstdc++-static` |
| SCons | 4.x (tested 4.11) | Fedora: `python3-scons` |
| MinGW-w64 GCC | tested 16.2 | Windows DLLs cross-compiled on Linux. Fedora: `mingw64-gcc-c++ mingw64-winpthreads-static` |
| MSVC 2022 | — | Optional: native Windows builds with `build_native.ps1` (not yet verified) |

Every pinned version is recorded in `versions.json`. `tests/unit/project/test_engine_pin.gd` fails if the running engine differs from the pin.

## Open, run and test

```sh
git clone <repo> && cd game
git lfs pull
godot --path . --editor          # open in the editor
tools/build/run_unit_tests.sh    # run all unit tests headless (Linux/macOS)
```

On Windows use `tools\build\run_unit_tests.ps1`. Both scripts read the engine binary from the `GODOT` environment variable (default `godot`), run an import pass, compile every script outside `addons/` (`tools/build/check_scripts.gd`), then run GUT over `tests/unit/` and write JUnit XML to `tests/reports/unit.xml` (or the path given as the first argument). They exit non-zero on any compile error or failing test.

### Building the native core

`lampblack_core` is the one C++ GDExtension. It lives in `native/`: engine-free code in `src/core/`, Godot bindings in `src/godot/`, doctest tests in `tests/`, and godot-cpp as a submodule pinned in `versions.json`.

```sh
git submodule update --init native/godot-cpp
tools/build/build_native.sh --test                     # Linux: debug + release libraries and doctest runners
tools/build/build_native.sh --platform windows --test  # Windows DLLs via MinGW; runners under Wine
tools/build/check_native_layering.sh                   # src/core/ engine-free; submodule at the pin
```

- Outputs go to `native/bin/`, which Git ignores. Release symbols are split into `native/bin/symbols/`; they are archived, never shipped.
- The script writes `native/godot-cpp/.gdignore`, so Godot never scans godot-cpp's own test project. Run it once after cloning, before opening the editor.
- The C++ runtime is linked statically. The Windows DLLs import only `KERNEL32` and `msvcrt`, so no redistributable is needed.
- Compiler rules (FND-06 determinism): C++17, `-ffp-contract=off` (`/fp:precise` on MSVC), never `-ffast-math`, `-Ofast` or `-march=native`. `LB_DEBUG_TOOLS` is defined only in `template_debug`.
- **No-root toolchain.** If the packages can't be installed system-wide, unpack their RPMs into `~/.local/opt/lampblack-toolchain/root/` (`dnf download --resolve ...` then `rpm2cpio | cpio -idm`). `build_native.sh` uses that toolchain whenever the folder exists; `LB_TOOLCHAIN` overrides the path.

### Running the server and client

One project runs both roles. `shared/boot/boot.tscn` (the main scene) picks the role from the build's feature tags and the launch arguments, then hands a typed `ServerConfig` or `ClientConfig` to `server/server_main.gd` or `client/client_main.gd`.

```sh
godot --headless --path . -- --server --exit-after-ticks 40   # dev server, stops after 40 ticks
godot --path .                                                # dev client (dev lobby placeholder)
godot --path . -- --connect 127.0.0.1:7777                    # dev client, direct connect
```

Put project arguments after `--`. Known flags placed before it, and Steam's `+connect_lobby <id>`, are also read. The full table is in FND-03. In release builds the dev-only flags (`--connect --no-steam --name --seed --qa-token --bot --exit-after-ticks`) are ignored with a warning. A malformed value exits with code 2 and prints the usage line.

| Exit code | Meaning |
|---|---|
| 0 | Clean end |
| 2 | Bad arguments |
| 3 | Build or protocol mismatch |
| 4 | Steam or game-server initialisation failed |
| 5 | Listen or bind failed |
| 10 | Drained |
| 70 | Unhandled fatal error |

### Exporting

Export templates for the pinned engine must be installed (`~/.local/share/godot/export_templates/4.7.2.stable/` on Linux). Verify the `.tpz` SHA-512 against `versions.json`.

```sh
tools/build/export_all.sh                 # every preset into build/<preset>/
tools/build/check_pack_contents.sh        # list each .pck and check the filter rules
tools/build/smoke_exports.sh              # run the QA builds with --exit-after-ticks 40
WINE=wine tools/build/smoke_exports.sh    # also run the Windows builds under Wine
```

| Preset | Mode | Tags | Shipped |
|---|---|---|---|
| `windows-client-qa`, `windows-client-release` | Normal | `lb_client` | The client depot (STM-12) |
| `linux-client-qa`, `linux-client-release` | Normal | `lb_client` | No: CI bots and developers |
| `windows-server-qa`, `windows-server-release` | Dedicated server | `lb_server` | Beside the client exe, for private hosts and Night Shift |
| `linux-server-qa`, `linux-server-release` | Dedicated server | `lb_server` | The fleet image only (STM-09) |
| `windows-client-killtest` | Normal | `lb_client lb_killtest` | QA-01's kill test |

- QA presets add `lb_qa` and use the debug template. Release presets add `lb_release` and use the release template. An export with neither flavour tag behaves as release.
- Client packs exclude `server/`; server packs exclude `client/` and strip visuals and audio. No pack contains `tests/`, `tools/` or GUT, and release packs drop every `debug/` folder.
- `export_presets.cfg` is generated by `tools/build/gen_export_presets.py`. Edit the table there, not the file.

## Engine pin policy

1. Pin the newest stable 4.x release for which all three exist: a GodotSteam GDExtension build (STM-01), a matching godot-cpp (FND-02) and a GUT release that supports it.
2. Record the exact version and the SHA-512 of the editor and export-template downloads for Windows and Linux in `versions.json`. FND-02 and STM-01 add their own pins to the same file.
3. Change the pin only at a milestone boundary, in one change that moves the engine, export templates, godot-cpp, GodotSteam and GUT together and passes CI.
4. Inside a milestone, a patch release (4.N.x) is allowed only for a blocking engine bug, under the same all-together rule.

**Current pin (M1):** Godot 4.7.2-stable, GUT 9.7.1. When it was chosen (2026-10-11), godot-cpp 10.0.0-stable targets it with `api_version=4.7`, and GodotSteam 4.23 ships builds for Godot 4.7.2 plus a GDExtension plugin.

## Layout

```
addons/            GodotSteam, GUT
native/            lampblack_core C++ (src/, tests/), godot-cpp submodule
shared/            constants, ids, tuning loader, protocol definitions
server/            sim/ systems/ creatures/ director/ world/ net/ modes/
client/            render/ audio/ ui/ input/ net/
data/              tuning/*.json, templates/, text/ (names, callouts, notes, lampman)
tests/             unit/ scenario/ fixtures/ support/
tools/             bots/ seed_harness/ stream_audit/ build/
```

`tests/unit/project/test_layout.gd` checks this layout.

## Coding conventions

- **Typed GDScript only.** These warnings are errors everywhere except `addons/`: `untyped_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_cast`, `unsafe_call_argument`, `unused_variable`, `shadowed_variable`, `unreachable_code`. Godot 4.7 sets the `addons/` exclusion through `debug/gdscript/warnings/directory_rules`.
  - Pull a `Variant` into a typed variable (`var d: Dictionary = value`) rather than casting with `as`, which counts as an unsafe cast.
  - Convert before passing a `Variant` to an untyped parameter (`str(x)`, a typed local), or `unsafe_call_argument` fires.
- `snake_case` file names. Use `class_name` only for types shared across files.
- **No tuning numbers in code.** They live in `data/tuning/` (FND-05).
- **Determinism** (FND-06; `tools/build/check_determinism_rules.sh` enforces 1, 3, 4 and 5 on `server/`, `shared/` and `native/src/core/`):
  1. All randomness comes from `LbHash` and `LbRng`: `LbRng.from_seed(LbHash.sub_seed(run_seed, HashDomain.X, keys, 0))`. Never use `randi`, `randf`, `randomize`, `RandomNumberGenerator`, `std::rand`, `std::random_device` or any `std::*_distribution`.
  2. Seed-derived decisions compare integers. Probabilities reach generation only as `Tuning.ppm()` integers (per million), so no float comparison decides a seed-derived choice.
  3. No transcendental maths (`sin cos exp log pow atan2`...) in seed-derived generation. `+ − × ÷` and `sqrt` are safe under the compiler flags.
  4. Never iterate a `std::unordered_*` container in a deterministic path. GDScript dictionaries iterate in insertion order, which is safe only when that order is itself deterministic.
  5. Simulation never reads the wall clock; time is the tick count. A justified exception ends its line with `# determinism: allow (<reason>)`.
- **Hash domains** live in `shared/ids/hash_domains.json`: append-only IDs, each registered by its owner ticket. `tools/build/gen_ids.gd` regenerates `shared/ids/hash_domains.gd` (`HashDomain`) and `native/src/core/generated/hash_domains.h`, and `--check` fails when either is stale.
- **Seeds are secret** (Gameplay §12.6). Reviewers check that no seed, sub-seed or `LbRng` state ever reaches a client message, lobby metadata, rich presence, a Timeline marker, telemetry or a release log. Dev and QA logs print seeds through `Log.dev()` as `LbHash.to_hex()`; release builds print nothing.
- **Golden values.** `native/tests/golden/rng_golden.json` and its C++ header are generated by `tools/build/gen_rng_golden.py` from the independent Python reference `tools/build/rng_reference.py`. Changing an algorithm, a constant or a domain ID needs a new `LbHash.VERSION`, with the old version kept for saves.
- **`server/` never loads from `client/`** (FND-03).
- **No physics** (GDD §15.8). No `RigidBody2D`, `CharacterBody2D`, `Area2D`, collision shapes, ray casts or physics-space queries in `server/` or `shared/`. Bodies are circles against solid tiles, stones fly a fixed arc and shots are rays. `tests/unit/project/test_no_physics_nodes.gd` enforces this.
- Tests are GUT scripts named `test_*.gd` under `tests/unit/`, extending `GutTest`.

## Vault note

This repository sits inside an Obsidian vault. The vault's `userIgnoreFilters` exclude `Implementation/game/`, so search and the graph skip code. Keep `.godot/` and build outputs out of any vault sync.
