# WendeComplementary

A fork of **Complementary Unbound r5.7.1** tweaked for **GT: New Horizons** (Minecraft 1.7.10 via Angelica).

Adds:
- Per-sprite albedo-luminance ray-marched displacement (IPBR).
- Generated reflective materials for GTNH casings and glass blocks.
- A few extra IPBR sliders (displacement curve, casing/glass reflectiveness).

## Install

1. Drop the whole shaderpack folder (or a zipped copy) into your instance's `shaderpacks/` directory.
2. **Copy the contents of `mods/` in this repo into your instance's `mods/` folder.** The pack relies on **Angelica** and **GTNHLib** at the bundled versions (or newer compatible builds) — without them the shader will not load correctly.
3. Launch the instance, open Video Settings → Shaders, and select the pack.

## Repo layout

- `shaders/` — the shader pack itself
- `mods/` — required mod jars (Angelica, GTNHLib)
- `scripts/` — generator for the reflective block lists in `shaders/block.properties`
- `DEVNOTES.md` — implementation notes

## Credits

Based on [Complementary Shaders — Unbound](https://www.complementary.dev/) by EminGT. See `License.txt`.
