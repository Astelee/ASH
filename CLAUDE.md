# CLAUDE.md — Ashfall Project Constitution

This file is binding. Read it before writing any code in this repo. If a request conflicts with
it, say so before you write the code.

**Engine:** Godot 4.5+ stable, **Mobile** renderer (Vulkan), GDScript with static typing.
**Target:** Android 16 (API 36), landscape, 1080×2400, mid-tier Snapdragon 7-series /
Dimensity 8000-class. 60 FPS target, 30 FPS floor on low tier.

Unity and Unreal are not on the table. Neither is switching to Forward+ to unlock an effect —
see [The never-do list](#the-never-do-list).

---

## 1. Language & style

### Static typing is mandatory

```gdscript
var hp: float = 100.0
var stamina := 100.0                      # inference is typing — fine, and preferred when obvious
func take_damage(pkt: DamagePacket) -> void:
```

Untyped GDScript is a bug, not a style choice. `gdscript/warnings/untyped_declaration` is set to
**error** in `project.godot`. Every `func` has a return type, including `-> void`.

### Naming

| Thing | Convention | Example |
|---|---|---|
| Script files | `snake_case.gd` | `attack_scheduler.gd` |
| Classes | `PascalCase` via `class_name` | `class_name AttackScheduler` |
| Scenes | `PascalCase.tscn` | `Husk.tscn` |
| Resource instances | `snake_case.tres` | `enemy_husk.tres` |
| Signals | `<noun>_<past_tense_verb>` | `poise_broken`, `ember_count_changed` |
| Constants / enums | `SCREAMING_SNAKE` / `PascalCase` members | `const COYOTE_TIME`, `enum State { IDLE }` |
| Private members | leading underscore | `_recovery_timer` |
| Booleans | read as an assertion | `is_grounded`, `has_attack_token` |

`class_name` on every reusable script. **One documented exception:** autoload scripts must *not*
declare a `class_name` matching their singleton name — a global class colliding with an autoload is
a hard parse error in Godot 4. The nine autoloads in `systems/` are therefore `class_name`-free.

### Node access

**Never** `get_node("../../Something")`. Ever. Three sanctioned patterns, in order of preference:

1. `@export var hurtbox: Hurtbox` — wired in the inspector, visible in the `.tscn` diff.
2. `@onready var sprite: MeshInstance3D = %Body` — `%` unique names, scene-local only.
3. Group lookups (`get_tree().get_first_node_in_group("player")`) for genuinely global singletons
   that are not autoloads.

A path that walks *up* the tree is a design error: the child is reaching for something it should
have been handed.

### No magic numbers in gameplay scripts

Every tuning value lives in a `Resource` under `res://data/tuning/*.tres`. If a designer (me) would
ever want to change it without a rebuild, it is data. Numbers that may stay in code: array indices,
`0.0`/`1.0` identity values, and physically fixed constants.

```gdscript
# WRONG
velocity.y = 9.5

# RIGHT
velocity.y = tuning.jump_velocity     # tuning: MovementTuning, from data/tuning/tuning_movement.tres
```

### Data-driven design

Enemies, weapons, armour, trinkets, items, biomes, moods, and status effects are `Resource`
subclasses — never hardcoded scripts. One `Enemy.tscn` reads one `enemy_husk.tres`. Adding an enemy
variant means adding a `.tres`, not a script.

### State machines are explicit

Every state machine is a `StateMachine` node with `State` children, each with
`enter()` / `exit()` / `physics_update(delta)` / `handle_input()`. No `if state == "attacking"`
chains, no `match` on a string. If you catch yourself adding a boolean like `is_attacking` next to
an existing state machine, the state machine is missing a state.

### Comments

`##` doc comments on every public method and every `@export` var — they surface in the editor
inspector and that is where I will read them. Inline comments explain **why**, never **what**. A
comment restating the code is deleted on sight.

---

## 2. Architecture

Three layers, and dependencies point one direction only:

```
Data (Resources)  →  Logic (plain classes)  →  Presentation (scenes / nodes)
```

- **Data** — `Resource` subclasses. No behaviour beyond validation and derived getters.
- **Logic** — plain `RefCounted`/`Object` classes. Damage math, XP curves, stat derivations, save
  migration, the attack-token scheduler. **No `Node` where avoidable**, because all of it must be
  unit-testable headless.
- **Presentation** — scenes and nodes. Reads logic results, plays animations, spawns VFX.

If damage math needs a node in the scene tree to run, it is written wrong and cannot be tested.

### Decoupling contracts

- The player scene must not know about any specific enemy scene, and vice versa. They know about
  `Hitbox`, `Hurtbox`, and `DamagePacket`. That is the entire shared vocabulary of combat.
- Cross-system communication goes through `EventBus`. Direct sibling calls between systems do not
  happen. `EventBus` carries **facts about the past** (`boss_defeated`), never commands
  (`kill_boss`); a command is a direct call on the system that owns the thing.
- Every scene is runnable in isolation with **F6** and degrades gracefully — a level with no
  `MoodDirector`-driving trigger still renders, an enemy with no player in the scene idles.

### Autoloads

Nine, registered in `project.godot`, all in `systems/`:

`EventBus` · `GameState` · `SaveSystem` · `AudioDirector` · `MoodDirector` · `QualityManager` ·
`InputRouter` · `SceneRouter` · `DebugOverlay`

**Do not add a tenth without asking.** An autoload is global mutable state; the bar is that at least
two unrelated systems need it and it has no sensible owner in the tree.

---

## 3. Performance budgets

Measured on mid tier, per frame, in the busiest legitimate gameplay moment (boss + adds + VFX):

| Budget | Limit |
|---|---|
| Draw calls | ≤ 130 |
| Triangles | ≤ 250,000 |
| Texture VRAM | ≤ 60 MB |
| Frame time | ≤ 16.6 ms (mid/high), ≤ 33.3 ms (low) |
| Materials per character | ≤ 3 |

### Lighting

- **One** shadow-casting `DirectionalLight3D`, 2 splits max, shadow distance 45 m.
- At most **2** shadow-casting `OmniLight3D` on screen at once. Every other point light is
  shadowless with a small radius.
- Static geometry uses **baked `LightmapGI`**. Dynamic actors sample the lightmap probes.
  No realtime GI. No SDFGI. The `.lmbake` outputs are committed.

### Geometry & materials

- All repeated props — grass, gravestones, torches, rubble, crowd fill, debris — use
  `MultiMeshInstance3D`. Not individual nodes. Not even "just for now."
- One texture atlas per biome wherever the art allows it.
- `alpha_scissor` for foliage and cutouts. **No alpha blending on anything covering significant
  screen area.** Mobile fill rate is the first thing that dies; overlapping transparent quads are
  how you get 22 FPS on a Mali GPU.

### Allocation

**Zero per-frame allocations in `_physics_process` and `_process`.** Object-pool: projectiles, hit
VFX, damage numbers, audio players, and impact decals. No `Array`/`Dictionary` literals constructed
per frame, no string formatting outside of debug-gated paths.

---

## 4. The never-do list

1. **Never use Forward+-only features.** Volumetric fog, SDFGI, SSAO, SSIL, SSR, subsurface
   scattering, and depth of field **do not exist on the Mobile renderer**. Every atmospheric effect
   is a deliberate fake — fog cards, god-ray cones, baked AO in the albedo/vertex colour, the
   single-pass grade shader. If you find yourself typing
   `environment.volumetric_fog_enabled = true`, stop and use the fog-card system.
   *Switching the project to Forward+ to unlock an effect is not a solution; it is a different game
   that runs at 25 FPS.*
2. **Never commit generated placeholder art.** Placeholders are Godot primitives (`BoxMesh`,
   `CapsuleMesh`, `CylinderMesh`) with the **real** material and shader applied, plus an entry in
   `docs/ASSET_MANIFEST.md` specifying exactly what the final asset needs: poly budget, texture
   size, material count, animation list. A grey capsule with the toon shader on it is useful. A
   procedurally generated "sword mesh" is landfill.
3. **Never invent an animation name.** `docs/ANIMATIONS.md` is the contract. Code reads names from
   constants, never string literals inline. Adding an animation means editing the doc first.
4. **Never build a system outside the current phase.** Noticed something the design needs? Write it
   in `docs/DEV_LOG.md` under "Deferred / suggested". Do not implement it.
5. **Never leave `print()` in code.** Use `Log.debug` / `Log.info` / `Log.warn` / `Log.error`
   (`systems/log.gd`), which are build-flag gated.
6. **Never write the save file in place.** Temp file, then rename. Android kills processes mid-write.
7. **Never scale `Engine.time_scale` for hitstop.** Freeze only the two actors involved via
   `AnimationPlayer.speed_scale` plus the shader hit flash. Global time scale wrecks input feel and
   desyncs the touch controls.
8. **Never commit a keystore or a password.** Reference environment variables. `.gitignore` covers
   `*.keystore`, `*.jks`, and `export_credentials.cfg` — do not defeat it.
9. **Never leave a `.tscn` unopenable in isolation.** If F6 on a scene crashes, it is broken even if
   the game runs.

---

## 5. Folder layout

```
res://
  actors/{player,enemies,npc,bosses}/   # character scenes + their scripts
  combat/                               # hitbox, hurtbox, damage packet, status effects
  systems/                              # autoloads + pure logic, no node deps where possible
  data/                                 # .tres Resources: stats, enemies, items, biomes, tuning
    tuning/ enemies/ items/ biomes/ stats/
  levels/{chunks,biomes,test}/
  art/{models,textures,materials,vfx,lut}/
  shaders/{surface,post,vfx}/
  ui/{hud,menus,components}/
  audio/{music,sfx,ambience,buses}/
  tests/                                # GUT tests
  tools/                                # editor plugins, build scripts
docs/                                   # GDD, TECH, PLAN, DEV_LOG, ANIMATIONS, ASSET_MANIFEST
scripts/                                # lint.sh, test.sh, build.sh, perf.sh
```

---

## 6. Definition of done (every phase)

A phase is not done until all of these are true:

1. `./scripts/lint.sh` exits 0 — gdformat clean, gdlint clean, every script parses and type-checks.
2. `./scripts/test.sh` exits 0 — GUT suite green, headless.
3. It runs on the **device**, not just the desktop editor, at the tier's target FPS.
4. Nothing that should be data is hardcoded.
5. `docs/DEV_LOG.md` has a dated entry: what was built, what was deferred, what is uncertain.
6. `docs/ASSET_MANIFEST.md` lists every placeholder introduced this phase.
7. Committed with a descriptive message.
8. A summary printed for review, then **stop**.

## 7. Mandatory test coverage

These have unit tests or the phase is not done: damage formula, mitigation curve, block absorption
and stability, XP/level cost curve, the Ember economy solve, stat derivations, save serialization
round-trip, save migration chain, attack-token scheduler.

---

## 8. Working style

- Phase gates are real. Do not start phase N+1 without approval.
- Deviating from the GDD or TECH spec is allowed — **say so explicitly in `DEV_LOG.md` with the
  reason**, in the same commit.
- When a spec value and the code disagree, the spec is right until I say otherwise.
- Uncertain about a design call? Build the part that does not depend on it, and ask.
