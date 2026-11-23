# Ashfall — Asset Manifest

Every placeholder in the project gets a row here, added **in the same commit that introduces it**
(`CLAUDE.md §4.2`). A placeholder is a Godot primitive with the real material/shader applied — never
generated binary art.

This file is the shopping list handed to a modeller or used to shop CC0 packs (Kenney, Quaternius,
Poly Haven). It must be complete enough to source assets from without opening the project.

## Columns

| Column | Means |
|---|---|
| **ID** | Stable identifier used in scene names and commit messages |
| **Placeholder** | What is in the project *right now* |
| **Needs** | The real asset |
| **Tris** | Triangle budget (mid tier) |
| **Textures** | Map set and resolution |
| **Mats** | Material count — **≤ 3 per character**, hard limit |
| **Anims** | Clip count; names live in `docs/ANIMATIONS.md` |
| **Phase** | Phase that introduced the placeholder |
| **Status** | `placeholder` · `sourced` · `final` |

---

## Characters

| ID | Placeholder | Needs | Tris | Textures | Mats | Anims | Phase | Status |
|---|---|---|---|---|---|---|---|---|
| `char_husk` | `CapsuleMesh` h 1.7 / r 0.35 + facing nub, brown `StandardMaterial3D` | Husk enemy model, rigged | ≤ 5,000 | albedo + normal + ORM, 1024² shared with the biome atlas | ≤ 2 | ~14 | 2 | `placeholder` |
| `char_cultist` | `CapsuleMesh` h 1.7, purple-grey | Crow-Mask Cultist, rigged | ≤ 5,000 | biome atlas | ≤ 2 | ~14 | 6 | `placeholder` |
| `char_warden` | `CapsuleMesh` h 1.9 + shield | Warden with a readable shield silhouette | ≤ 6,000 | biome atlas | ≤ 3 | ~16 | 6 | `placeholder` |
| `char_wretch` | `CapsuleMesh` h 1.1, low crawler | Gravewretch, quadrupedal | ≤ 3,500 | biome atlas | ≤ 2 | ~12 | 6 | `placeholder` |
| `char_bell_bearer` | `CapsuleMesh` h 2.0 + bell | Bell-Bearer; the bell must read at distance | ≤ 6,000 | biome atlas | ≤ 3 | ~14 | 6 | `placeholder` |
| `char_cadwyn` | `CapsuleMesh` h 2.6 r 0.55, rust red | Ser Cadwyn, rigged, two-phase visual change | ≤ 12,000 | dedicated 2048² | ≤ 3 | ~24 | 6 | `placeholder` |
| `vfx_rot_flask` | `SphereMesh` r 0.18 | Thrown flask + rot burst VFX | n/a | atlas | 1 | 6 | `placeholder` |
| `char_player` | `CapsuleMesh` h 1.8 / r 0.35 + a `BoxMesh` facing nub, grey `StandardMaterial3D` | Player character model, rigged, humanoid | ≤ 8,000 | albedo + normal + ORM, 1024² atlas | ≤ 3 | 32 (see `ANIMATIONS.md`) | 1 | `placeholder` |

The facing nub is a deliberate stand-in for the *readability* the real silhouette must provide: at
29 % of screen height you have to be able to tell which way the player faces in one glance. Any
replacement model that fails that test is not finished, whatever its poly count.

> **Materials note.** The capsule carries a plain `StandardMaterial3D`, **not** the real
> `character_pbr` shader, because that shader does not exist until Phase 4. This is the one
> place Phase 1 falls short of the "placeholders wear the real material" rule in `CLAUDE.md §4.2` —
> unavoidable, and resolved by Phase 4 rather than deferred indefinitely.

## Props & environment

| ID | Placeholder | Needs | Tris | Textures | Mats | Phase | Status |
|---|---|---|---|---|---|---|---|
| `village_greybox` | ~20 `CSGBox3D` terraces, walls and lanes with `mat_terrain` | Ashfall Village art: street, buildings, gatehouse, three backdrop silhouettes | ≤ 40,000 total | one biome atlas, 2048² | 2 | 5 | `placeholder` |
| `village_grass` | `QuadMesh` 0.5×0.6 on `mat_foliage`, 220 scattered | Grass cards, alpha-cut | ≤ 4 tris each | shared biome atlas | 1 | 5 | `placeholder` |
| `gym_geometry` | 16 × `CSGBox3D`, `use_collision = true`, two grey materials | **Nothing.** `levels/test/movement_gym.tscn` is a permanent test fixture, not a shipping level. | n/a | n/a | 2 | 1 | `fixture` |

CSG is the right tool here and is not technical debt: the gym exists to be edited whenever a
movement value changes. It never ships, so the `MultiMeshInstance3D` rule in `CLAUDE.md §3` does not
apply to it. Every measurement in it is derived from `tuning_movement.tres` — the 2.0 m walk gap,
the 3.5 m sprint gap, the 5.5 m impossible gap, the 5.6 m ledge wall, and the 11 m fall-damage drop.

## UI

| ID | Placeholder | Needs | Format | Phase | Status |
|---|---|---|---|---|---|
| `ui_touch_glyphs` | `^` and `»` drawn as text in `TouchButton` | Real action icons, legible at 9 mm on a sunlit phone | SVG → atlas | 1 | `placeholder` |
| `vfx_hit_flash` | shader uniform exists and is now per-instance; **no driver writes it yet** | The white-lerp flash on every hit | shader uniform | 2 | `blocked on Phase 4` |
| `ui_damage_numbers` | `Label3D` with the default font | Styled numerals, legible at arm's length | font + outline | 2 | `placeholder` |
| `ui_joystick_ring` | `draw_arc` / `draw_circle` primitives | Styled stick base + knob art | SVG → atlas | 1 | `placeholder` |

## Textures, LUTs & VFX

| ID | Placeholder | Needs | Format | Size | Phase | Status |
|---|---|---|---|---|---|---|
| — | — | *nothing yet* | | | | |

## Audio

| ID | Placeholder | Needs | Format | Phase | Status |
|---|---|---|---|---|---|
| `sfx_footsteps` | **none** — empty banks | 3–4 takes per surface × 7 surfaces (stone, gravel, wood, grass, water, bone, metal) | OGG mono 44.1k | 8 | `missing` |
| `sfx_combat` | **none** | Light/heavy/riposte impacts, shield block, parry ring, guard break, poise break | OGG mono | 8 | `missing` |
| `sfx_tells` | **none** | **Gravewretch rattle** and **Bell-Bearer bell** — gameplay signals, must read through walls and be directionally clear | OGG mono | 8 | `missing` |
| `music_stems` | **none** | 5 sample-locked stems per biome: drone, low strings, percussion, lead, choir | OGG stereo, identical length | 8 | `missing` |
| `amb_beds` | **none** | Looping ambience per biome | OGG stereo | 8 | `missing` |
| `sfx_ui` | **none** | Menu move/confirm/back, level-up, boss sting | OGG mono | 8 | `missing` |

---

**Phase 0 introduced no placeholders** — no gameplay code, no scenes, no art.

## Style guidance (from the brief, §6)

Stylized low-poly with hand-painted-looking textures survives mobile far better than
semi-realistic — and it is what makes the toon shader sing. Source everything to that target;
mixing a semi-realistic pack into a stylized set costs more time to fix than it saves.


## Textures the realism pass needs (2026-08-15)

Every material below currently samples `hint_default_white`, which means the code path is live and
contributing nothing. These are the assets that turn the PBR overhaul from wiring into pixels.

| Asset | Purpose | Size | Notes |
|---|---|---|---|
| `orm_character.png` | Occlusion / roughness / metallic, packed R/G/B | 1024² | One fetch instead of three. Linear, **not** sRGB |
| `detail_normal_cloth.png` | Tight-tiled weave for the character shader at 9x | 512² | Tiling; normal-map import preset |
| `detail_normal_ground.png` | Same job on terrain at 6x | 512² | Tiling |
| `macro_noise.png` | Low-frequency terrain variation, ~40 m per repeat | 256², greyscale | Breaks visible tiling — the biggest single tell on ground |
| `lut_<biome>.png` | 32×32×32 colour-grade strip, one per biome | 1024×32 | Fed to `Environment.adjustment_color_correction` |

Until these exist, the shaders render as flat-roughness untextured PBR. That is a legitimate
greybox state under `CLAUDE.md §4.2` — the real shader is applied and the real uniforms are wired —
but it is not the finished look.

---

## Placeholders introduced 2026-08-15 (orphan sweep)

| Placeholder | Primitive | Real material applied | What the final asset needs |
|---|---|---|---|
| `Bloodstain` marker | `CylinderMesh`, 10 segments, 0.9 m | `mat_bloodstain` on `emissive_flicker` | A drifting ember-mote particle wisp, not a solid mesh. ~200 tris, 1 material, 256² alpha sheet, no animation clips — the flicker is already in the shader |

The bloodstain also carries a shadowless `OmniLight3D` at 4.5 m. That is deliberate and should
survive into the final asset: it is the only thing that makes the pickup findable through fog, and
`CLAUDE.md §3` allows two shadow-casting omnis on screen — this is not one of them.

---
