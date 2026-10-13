# Third-party components

Every third-party component in the game, with its version and licence. This list feeds the store's legal and credits review (STM-13). Add a row whenever a component is added or its pin moves.

| Component | Version | Licence | Location | Source |
|---|---|---|---|---|
| Godot Engine | 4.7.2-stable | MIT | Engine and export templates (not vendored) | https://godotengine.org |
| GUT (Godot Unit Test) | 9.7.1 | MIT | `addons/gut/` (licence: `addons/gut/LICENSE.md`) | https://github.com/bitwes/Gut |
| godot-cpp | 10.0.0-stable (`507ed9d`) | MIT | `native/godot-cpp/` (submodule) | https://github.com/godotengine/godot-cpp |
| doctest | 2.5.3 | MIT | `native/thirdparty/doctest/` (licence: `LICENSE.txt`); test builds only | https://github.com/doctest/doctest |
| Anonymous Pro, Courier Prime, Lobster Two fonts (bundled with GUT) | as shipped in GUT 9.7.1 | SIL OFL 1.1 | `addons/gut/fonts/` (licence: `addons/gut/fonts/OFL.txt`) | Bundled with GUT |

GUT is a development tool and is excluded from release exports (FND-03).
