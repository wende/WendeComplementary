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

### Optional: track your in-game settings in this repo

OptiFine/Iris saves the values you set in the shader options menu to a sibling
file next to the pack folder: `shaderpacks/ComplementaryUnbound_r5.7.1_optimized.txt`.
A copy of that file lives at `settings/ComplementaryUnbound_r5.7.1_optimized.txt`
in this repo. To make the launcher read/write the repo copy directly, replace the
sibling with a symlink:

```sh
cd <instance>/.minecraft/shaderpacks
mv ComplementaryUnbound_r5.7.1_optimized.txt ComplementaryUnbound_r5.7.1_optimized.txt.bak
ln -s ComplementaryUnbound_r5.7.1_optimized/settings/ComplementaryUnbound_r5.7.1_optimized.txt \
      ComplementaryUnbound_r5.7.1_optimized.txt
```

After that, any changes you make in the in-game shader menu land in the repo and
can be committed.

## Repo layout

- `shaders/` — the shader pack itself
- `mods/` — required mod jars (Angelica, GTNHLib)
- `scripts/` — generator for the reflective block lists in `shaders/block.properties`
- `settings/` — saved shader option values (target of the sibling-`.txt` symlink)
- `DEVNOTES.md` — implementation notes

## Credits

Based on [Complementary Shaders — Unbound](https://www.complementary.dev/) by EminGT. See `License.txt`.
