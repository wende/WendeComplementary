# Dev Notes — Session Summary

## Where the repo currently sits

`HEAD` is at `6b35c6c` (per-sprite displacement with writable `texCoord` macro,
**before** the clamp fix). Build is working, displacement looks correct on
single sprites, shadows fall on the displaced surface (not baked into the
heightmap).

Commits past this point are reachable in the reflog only — `git reflog` to find
them if you want to bring any back.

## What got built and what got abandoned

### Kept

- **Per-sprite albedo-luminance displacement** (`03d0ce5` → `6b35c6c`).
  Lives in `gbuffers_terrain` only. Marches the camera ray against an
  atlas-tile-local heightmap derived from RGB→luminance of the diffuse
  texture. Toggle: `GENERATED_DISPLACEMENT` in IPBR settings, with
  `_DEPTH` / `_QUALITY` / `_DISTANCE` sliders.
  - Reuses the POM varyings (`viewVector`, `vTexCoordAM`, `tbnMatrix`) by
    force-defining `POM` when the toggle is on, without enabling the
    labPBR-targeted `customMaterials.glsl` path.
  - Required adding `GENERATED_DISPLACEMENT_NEEDS_TBN` to the
    `tangent`/`binormal` gates in `gbuffers_block`, `_water`, `_entities`,
    `_hand` so they compile when `POM` is forced on but `GENERATED_NORMALS` /
    `CUSTOM_PBR` are off.
  - `texCoord` is a fragment varying (read-only). To make `GenerateNormals`
    and other downstream code see the displaced coord, there's a macro hack
    in `gbuffers_terrain.glsl`: shadow it with a writable global of the same
    name. The vertex shader's `out vec2 texCoord;` is unaffected because the
    macro lives inside `#ifdef FRAGMENT_SHADER`.

### Abandoned (reachable via reflog)

- **Clamp-not-fract for sprite edge** (`bec53ec`).
  Replaces `fract()` with `clamp()` in the sprite→atlas conversion so a ray
  exiting the tile stops at the edge column instead of wrapping to the
  opposite side. Fixes the "duplicated underlying texture at block
  boundaries" artifact. Reverted because the user's screenshot showed the
  pre-clamp state actually looked better in their gameplay context. Worth
  re-evaluating if duplication artifacts come back.

- **Deferred screen-space march** (`71c6362`).
  Moved displacement out of `gbuffers_terrain` into `deferred1`. Reconstructs
  surface normal from depth gradient, projects the view-tangent to screen,
  marches `colortex0`. Goal was to pull *real* neighbor-block content into
  the displaced position instead of clamp's edge-stretch.
  - **Killer artifact**: heightmap is sampled from `colortex0`, which is
    *lit* color at this stage. Shadows, AO, fog all get baked in. Result:
    every shadow on flat ground reads as a depression, producing severe
    visual distortion.

- **Raw-albedo gbuffer (`colortex9`)** (`d5f4c23`).
  Attempt to fix the lit-heightmap problem by writing pre-lighting albedo
  from `gbuffers_terrain` to a dedicated buffer that the deferred march
  could read instead of `colortex0`. Reverted because something about it
  broke the visuals worse than the shadow-as-depression artifact, and the
  user couldn't pinpoint what. Plausible suspects (not verified):
  - `gl_FragData[2]` getting bound to the wrong colortex when DRAWBUFFERS
    layout flipped between `06`, `064`, `069`, `0649` cases.
  - Other gbuffers programs (water, entities, hand) writing
    `gl_FragData[2]` to colortex4 (normal) — but if any of them clear or
    overwrite colortex9 the heightmap goes black.
  - Iris parsing the unconditional `colortex9Format` / `colortex9Clear`
    differently from declarations gated by `#ifdef`.

  If revisited, validate one assumption at a time: first make sure
  `colortex9` is allocated and clear-on-frame works, then verify only
  `gbuffers_terrain` writes to it, then verify `deferred1` reads sane
  values out of it. A single screenshot of the buffer dumped raw to the
  screen would have caught whichever one was wrong.

## Still-open concerns at `6b35c6c`

1. **Gradient textures render as slopes.** Fundamental to albedo-as-height:
   if a sprite is bright on one side and dark on the other, the heightmap
   tilts. There's no signal in the albedo to distinguish "intended visual
   gradient" from "depth gradient". Mitigations are heuristic
   (e.g. nonlinear contrast on luminance to flatten mid-tones), no clean
   fix available.

2. **Block boundaries** show edge-column stretch (when clamp is in) or
   wrap-duplication (when clamp is out — current state). The proper fix
   needs cross-block visibility, which means screen-space sampling, which
   requires the raw-albedo buffer to work. See abandoned items above.

3. **Block entities, water, hand items** don't participate. Only
   `gbuffers_terrain` was wired up. If displacement is wanted on chests,
   signs, pistons, etc., the same logic needs to be inserted in
   `gbuffers_block.glsl` (and the other relevant programs).

## Performance baseline

User reported +12% FPS (58 → 65) from the perf-only commits
(`fd5dbf2`–`5c48a64`) before any displacement work. Per-sprite displacement
on top of that costs `GENERATED_DISPLACEMENT_QUALITY` extra texture reads
per terrain pixel in the worst case (default 64). On the user's M1 Max
hardware this was acceptable.

## Pipeline-level facts learned this session

- `texCoord` in fragment shaders is `in` (read-only). Mutable downstream
  use requires either (a) renaming the varying everywhere or (b) the
  macro-shadow trick used in `gbuffers_terrain.glsl`.
- `signMidCoordPos` is the per-pixel sign offset from sprite center
  (interpolated in {-1,0,+1}); `vTexCoord = signMidCoordPos * 0.5 + 0.5`
  gives a sprite-local 0..1 coord. `vTexCoordAM.{st, pq}` holds sprite
  origin and size on the atlas. `vTexCoord * vTexCoordAM.pq + vTexCoordAM.st`
  reconstructs the atlas coord, equivalent to `texCoord` modulo precision.
- `dFdxdFdy.glsl` declares `dcdx` / `dcdy` at file scope from
  `dFdx(texCoord)` / `dFdy(texCoord)`. Always pass these as the gradient
  args to `textureGrad` when sampling at a perturbed coord — otherwise the
  GPU derives mip from the perturbed coord's derivatives, which spike at
  `fract()` discontinuities and pull garbage from low-res mips at sprite
  edges.
- Atlas-edge bleed (1-pixel gray seams between blocks) needs a half-texel
  inset clamp on top of `textureGrad` — bilinear filtering at the exact
  sprite edge fetches the neighbor sprite's pixel even when mip is right.
- DRAWBUFFERS directives map `gl_FragData[N]` indices to colortex slots in
  declaration order, *not* by colortex index. `DRAWBUFFERS:069` means
  `[0]→colortex0`, `[1]→colortex6`, `[2]→colortex9`. Forgetting this
  causes silent corruption.
- Iris parses `const bool colortexNClear` and `const int colortexNFormat`
  from any included `.glsl` file. Wrapping them in `#ifdef` may or may not
  work depending on Iris version — safest to declare unconditionally.
- Forcing `#define POM` globally cascades through every gbuffers program;
  any program with a `#ifdef POM` block that uses `tangent`/`binormal`
  (which they all do) will then need those varyings available, even if
  `CUSTOM_PBR` and `GENERATED_NORMALS` are off.

## Reading order for next session

1. `shaders/lib/common.glsl` — `GENERATED_DISPLACEMENT*` defines around
   line 211, `#define POM` cascade in the RP_MODE block.
2. `shaders/program/gbuffers_terrain.glsl` — `texCoord` macro shadow at the
   top, displacement call site after `lViewPos` is computed, before
   `terrainIPBR.glsl` include.
3. `shaders/lib/materials/materialMethods/generatedDisplacement.glsl` —
   the actual march (`SpriteToAtlasClamped`, `GetGeneratedDisplacementCoord`).
4. The four other `gbuffers_*.glsl` for the `GENERATED_DISPLACEMENT_NEEDS_TBN`
   gate additions.
