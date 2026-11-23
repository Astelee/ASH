# Ashfall — Phase Plan

**The phase gate is the quality lever.** No phase starts without approval of the previous one. Every
phase ends the same way:

> run `./scripts/lint.sh` → run `./scripts/test.sh` → update `docs/DEV_LOG.md` → update
> `docs/ASSET_MANIFEST.md` → commit with a descriptive message → print
> **done / deferred / uncertain** → **stop and wait for review.**

**Universal definition of done** (in addition to each phase's own): lint gate green, test suite
green, runs on the *device* at the tier's target FPS, nothing hardcoded that should be data, DEV_LOG
entry written, committed.

---

## Phase 0 — Foundations ✅ *(this phase)*

**Deliverables:** `README.md`, `CLAUDE.md`, `docs/GDD.md`, `docs/TECH.md`, `docs/PLAN.md`,
`docs/DEV_LOG.md`, `docs/ANIMATIONS.md`, `docs/ASSET_MANIFEST.md`, `project.godot` fully configured,
folder skeleton with `.gdkeep`, nine autoload stubs, `Log`, `.gitignore`, `.editorconfig`,
`scripts/lint.sh`.

**Acceptance:** the project opens in Godot 4.5 on the Mobile renderer with no errors, all nine
autoloads resolve, all ten input actions respond on keyboard and gamepad, and the docs are specific
enough to argue with.

**Done when:** reviewed and committed. **No gameplay code.**

---

## Phase 1 — Movement, camera, controls, greybox ✅ *(code complete; device check outstanding)*

**Deliverables**
- `actors/player/Player.tscn` + controller implementing the full movement table from `GDD.md §5`.
- `data/tuning/tuning_movement.tres` (`MovementTuning` Resource) — every value from that table.
- Camera rig: asymmetric damping (0.12 s H / 0.28 s V), 1.8 m look-ahead, 0.6 m dead zone, vertical
  snap only when grounded. `data/tuning/tuning_camera.tres` — **FOV 42, camera Z +8.0** (revised
  from the spec's +12.5; see `GDD.md §4`). Verify the framing on the phone and expect to move Z.
- Coyote time (0.12 s) + jump buffer (0.15 s), ledge grab, landing recovery, fall damage.
- `InputRouter`: dynamic virtual joystick (left 40 %, 12 % dead zone, 140 px radius) + button layer,
  safe-area insets from `DisplayServer.get_display_safe_area()`, keyboard/gamepad parity.
- `levels/test/movement_gym.tscn` — platforms, gaps, slopes at and above the 46° walk limit, a
  grabbable ledge, and a > 6 m drop for fall damage.
- `DebugOverlay` live: FPS, frame time, draw calls, primitives, VRAM, quality tier.
- Player `StateMachine` with real states: `Idle`, `Run`, `Jump`, `Fall`, `LedgeGrab`, `Land`.

**Acceptance criteria**
1. Playable on device at 60 FPS.
2. Coyote time and jump buffer are individually demonstrable in the gym.
3. Camera does not bob during jumps.
4. Touch targets measure ≥ 9 mm on the actual phone, and the player reads at ~29 % of screen height.
5. Changing a value in `tuning_movement.tres` changes the feel with **no code edit**.
6. `Player.tscn` runs standalone on F6.

**Explicitly out of scope:** combat, enemies, health, any UI beyond the debug overlay.

> **Status.** Criteria 2, 3, 5, and 6 verified headless by `tests/MovementCheck.tscn`. Criteria 1
> (60 FPS on device) and 4 (9 mm targets on a real panel) are **outstanding — no Android hardware
> has been attached.** The touch layer has never received a real finger. See `DEV_LOG.md`.

---

## Phase 2 — Combat core ✅ *(code complete; device + latency check outstanding)*

**Deliverables**
- `combat/`: `Hitbox`, `Hurtbox`, `DamagePacket`, `StatusEffect` base.
- Attack state machine: windup → active → recovery, with the exact timings from `GDD.md §6.1`.
- 3-hit light combo with the 0.45 s window; heavy with charge to 1.20 s; dodge with i-frames
  0.08 → 0.32 s; poise and guard break.
- Block via the **shield absorption + stability** model (`GDD.md §6.1b`), not double mitigation.
- Parry with a **device-dependent window** — 0.18 s button / 0.24 s touch — plus the **touch-latency
  instrumentation** described in `TECH.md §6`. The 0.24 s value is a guess until measured; the
  measurement goes in `DEV_LOG.md`.
- Hitstop (60/110/180 ms) — **per-actor `AnimationPlayer.speed_scale`, never `Engine.time_scale`.**
- Hit flash via `character_toon_pbr`'s `hit_flash` uniform; pooled damage numbers.
- `actors/enemies/Husk.tscn` + `data/enemies/enemy_husk.tres`, full AI state machine
  (`Idle → Alert → Approach → Attack → Recover → Reposition → Stagger → Dead`).
- `combat/attack_scheduler.gd` — the 2-token system, as a plain testable class.
- `data/tuning/tuning_combat.tres`; `systems/damage.gd` as a pure logic class.
- GUT tests: damage formula (multi-stat scaling sum), mitigation curve, **block absorption +
  stability**, attack scheduler.

**Acceptance criteria**
1. Fight three Husks at once and never face more than two attacking simultaneously.
2. Parry one; it enters the 1.5 s riposte-vulnerable state and I gain 15 stamina.
3. Get poise-broken by one and take a ×2.2 riposte hit.
4. Numbers on screen match `GDD.md §6.4` — the worked example lands on **43**.
5. Measured p90 touch latency is recorded, and `parry_window_touch` is derived from it rather than
   assumed.
6. `./scripts/test.sh` green.

**Explicitly out of scope:** XP, Embers, death, saving, other enemies.

> **Status.** Criteria 1–4 and 6 verified headless by the GUT suite plus `tests/CombatCheck.tscn`.
> Criterion 5 (**measured p90 touch latency**) is **outstanding — it requires a device**, and the
> shipped `parry_window_touch = 0.24` remains the unvalidated estimate. Hit flash also waits on the
> Phase 4 shader. See `DEV_LOG.md`.

---

## Phase 3 — Progression & persistence ⚠️ *(systems done and tested; UI and respawn outstanding)*

**Deliverables**
- Stat system (Vigor / Endurance / Might / Finesse / Ember-Bound) with the derivations and the Vigor
  soft cap; `systems/progression.gd` holding `cost(level)` as the single source of truth.
- Embers: drops, carry, spend, and the **per-biome `ember_multiplier`**. Wayshrine scene with rest +
  level-up + stat allocation UI.
- **The Ashen Flask** (`GDD.md §7.7`): 3 charges, 1.10 s committed drink with the heal landing at
  0.55 s, Ember-Bound potency scaling, Ash Shard charge upgrades, refill on rest.
- Death → bloodstain → recovery loop, including losing it on a second death.
- Enemy respawn on rest; boss defeat states persist.
- `SaveSystem`: gzip JSON, checksum header, temp-file-then-rename, `.bak` rotation, migration chain
  scaffolding, autosave on rest / level-up / boss defeat / `NOTIFICATION_APPLICATION_PAUSED`.
- GUT tests: cost curve + cumulative, stat derivations, save round-trip, migration chain.

**Acceptance criteria**
1. Level up at a Wayshrine and see HP/stamina change per the table.
2. Drinking mid-combat is punishable — the heal arrives at 0.55 s, not on the first frame.
3. Die, lose Embers to a bloodstain, recover them.
4. Die again before recovering → they are gone.
5. **Force-close the app mid-run and reopen to the correct state.**
6. A hand-edited v1 save loads through the migration chain into the current version.
7. A full clear of the test encounters pays out roughly the Embers §7.2b predicts.

> **Status.** Progression, the save system with migrations, the flask, and the death loop are built
> and covered by 85 passing tests. **Not done:** the stat-allocation UI (deferred to Phase 7, which
> owns UI), enemy respawn on rest (needs Phase 5's level tooling), and bloodstain placement into a
> loaded level. Criterion 5 is unverified on a device. See `DEV_LOG.md`.

---

## Phase 4 — Rendering, shaders, mood ⚠️ *(built and compiling; LUT pipeline outstanding, look and perf unjudged)*

**Deliverables**
- All nine shaders from `TECH.md §2`, each with documented uniforms.
- Material library in `art/materials/`, one atlas convention per biome.
- `MoodDirector` + the `BiomeMood` Resource, with all four biome moods authored as `.tres`.
- `QualityManager`: three tiers, 3-second benchmark auto-detect, user override, dynamic resolution
  with the boss-telegraph hold flag.
- Fog-card MultiMesh system and the god-ray cone system.
- LUT pipeline: 32×32×32 strip authoring, biome blending, `post/grade_and_grain` as the **single**
  fullscreen pass.
- One showcase scene transitioning **Ashfall Village → Ossuary Deep**.

**Acceptance criteria**
1. The eerie shift is legible on device, in one continuous transition.
2. Holds 60 FPS on mid tier inside the budgets in `CLAUDE.md §3`.
3. **Retuning the entire mood of an area means editing one `.tres`** — no code, no scene edits.
4. Low tier holds 30 FPS with shadows off.

> **Status.** All nine shaders, `MoodDirector`, `BiomeMood`, four moods, `QualityManager`,
> `FogCardField`, `LevelRoot`, `MoodTrigger`, the material library, and
> `levels/test/mood_showcase.tscn` (village to Ossuary and back) are built. Every shader
> compiles on a real GPU under a gate stage. **Not done:** the LUT pipeline (needs authored LUT
> textures and the post-process ColorRect mounted) and god-ray placement. **Criteria 1 and 2
> cannot be self-assessed** - the look is your judgement and 60 FPS needs the device.
> See `DEV_LOG.md`.

---

## Phase 5 — Level tooling & Biome 1 ⚠️ *(tooling + village greybox built; device perf outstanding)*

**Deliverables**
- Chunk-based level assembly: hand-placed chunks with snap points. **Not procedural.**
- Spawn markers, encounter volumes, trigger volumes wired to `MoodDirector`.
- Depth-lane parallax backdrop system (Z −6 / −14 / −40 per `GDD.md §4`).
- `MultiMesh` prop-scattering tool as an editor plugin in `tools/`.
- The complete playable **Ashfall Village**: Wayshrines, a shortcut unlock, 3 enemy encounters.
- Baked `LightmapGI` for the whole level, committed.

**Acceptance criteria**
1. **I can build a new area by dragging chunks together in the editor without writing code.**
2. Village runs at 60 FPS on mid tier, within draw-call and triangle budgets.
3. The shortcut makes the second traversal materially shorter.

> **Status.** Tooling and **Ashfall Village** are built: two Wayshrines, three encounters (8 Husks),
> a shortcut gate, three parallax lanes, a fog field, and scattered grass. Criteria 1 and 3 are
> asserted in `test_village.gd` — the shortcut test measures both routes and requires it to save
> ≥ 80 % of the walk. **Criterion 2 (60 FPS on mid tier) needs the device.** Greybox primitives,
> logged in `ASSET_MANIFEST.md`. See `DEV_LOG.md`.

---

## Phase 6 — Enemy roster & first boss ⚠️ *(built and tested; never played)*

**Deliverables**
- All five enemy types with distinct movesets and the tells from `GDD.md §9`: Husk, Crow-Mask
  Cultist, Warden, Gravewretch, Bell-Bearer.
- The Gravewretch off-screen audio cue and the Bell-Bearer's through-wall bell.
- **Ser Cadwyn the Rusted:** 2 phases with the transition at 55 % HP, arena setup, fog gate, boss HP
  bar, phase-transition cinematic camera, death sequence, persistent defeat state.
- Boss telegraph → `QualityManager` hold-flag integration.

**Acceptance criteria**
1. Each enemy is identifiable by its tell alone, with the screen half-covered.
2. The Warden is genuinely parry-or-flank; trading with it loses.
3. Cadwyn's phase 2 is a readable escalation, not a stat bump.
4. Killing Cadwyn persists across a force-close.

> **Status.** All five enemies and Ser Cadwyn are built, with distinct archetypes: ranged + retreat,
> frontal shield, telegraphed lunge, and an ally aura. Two phases at 55 %, fog gate, HP bar with
> phase ticks, persistent defeat. 138 tests assert every stat and resistance against the GDD tables.
> **Criteria 1–3 are judgement calls that need play**, and criterion 4 needs a device. See
> `DEV_LOG.md`.

---

## Phase 7 — UI/UX & accessibility ⚠️ *(systems + gameplay screens built; settings screen and main menu outstanding)*

**Deliverables**
- Main menu, HUD (HP / stamina / Embers / lantern, readable at arm's length), pause, death screen,
  loading screens.
- Settings: **control layout editor**, quality tier, audio mix, brightness, damage-numbers toggle,
  colourblind palettes, hold-vs-toggle sprint/block, reduced camera shake, subtitle size.
- Localization scaffolding — **every string in a CSV**, no literals in UI scenes.

**Acceptance criteria**
1. Readable at arm's length on the actual phone, in sunlight.
2. The control layout editor survives a save/load round-trip.
3. Colourblind palettes preserve the saturation arc that carries the mood.
4. No user-facing string exists outside the CSV.

> **Status.** `Settings` (every option, persisted separately from the save), `ui/strings.csv` (64
> keys), `PlayerHud`, `PauseMenu`, `DeathScreen`, and `StatAllocation` are built and covered by 151
> passing tests. **Not done:** the settings *screen*, the main menu, loading screens, the
> drag-to-move layout editor (offsets persist and round-trip; the dragging UI does not exist), and
> the colourblind palettes are an enum with no LUTs behind them — blocked on the same Phase 4 LUT
> pipeline. Criterion 1 (readable at arm's length in sunlight) needs the device. See `DEV_LOG.md`.

> **This is the natural stopping point for a vertical slice.** After Phase 7 the game is Biome 1,
> complete, polished, and shippable. See `§Scope reality` below.

---

## Phase 8 — Audio ⚠️ *(systems built and tested; no audio assets exist)*

**Deliverables**
- Bus layout: Master / Music / SFX / Ambience / UI, plus a reverb send per zone.
- Surface-tagged footsteps.
- Layered music responding to `MoodDirector` state **and** combat state (the stem mask from
  `BiomeMood`).
- Positional SFX through an object-pooled player.
- The Gravewretch and Bell-Bearer audio tells as first-class gameplay signals.
- Ducking rules (combat over ambience, UI over everything).

**Acceptance criteria**
1. Entering the Ossuary drops the mix to drone-only on the same curve as the visual transition.
2. The Gravewretch lunge is survivable **on audio alone**, eyes on the other side of the screen.
3. Zero audio-player allocations during combat.

> **Status.** Bus layout, pooled voices with priority stealing, `SoundBank` variation, five-stem
> music mixing, ducking with hold and release, distance-driven footsteps, ground-tagged surfaces,
> and the telegraph hook are built and covered by 175 passing tests. Criterion 3 is asserted.
> **No audio assets exist** — every bank is empty until sound is sourced, so criteria 1 and 2 are
> unhearable. See `DEV_LOG.md`.

---

## Phase 9 — Ship pass ⚠️ *(tooling + budget gate built; every device measurement outstanding)*

**Deliverables**
- Profiling against every budget in `CLAUDE.md §3`; texture atlasing; draw-call reduction.
- Memory-leak pass; `NOTIFICATION_APPLICATION_PAUSED` / `RESUMED` correctness.
- Thermal behaviour verified over a **20-minute** continuous session.
- AAB export, signing pipeline, 16 KB alignment verification, store checklist.
- `docs/ASSET_MANIFEST.md` complete: every placeholder that still needs real art.

**Acceptance criteria**
1. All budgets met on mid tier during the worst-case encounter.
2. No sustained frame-time degradation after 20 minutes (thermal throttle handled by the dynamic
   resolution, not by a stutter).
3. A signed AAB uploads to the Play Console without warnings.
4. `zipalign -c -P 16` verification passes.

> **Status.** The budget gate measures real scenes with a real renderer — **Village 27 draw calls /
> 8,152 tris, Arena 10 / 7,008**, both well inside the limits. `scripts/build.sh` (with 16 KB
> alignment verification) and `scripts/perf.sh` (with a 20-minute thermal mode) are written, as are
> the pause/resume and leak tests and `docs/STORE_CHECKLIST.md`. **Every on-device measurement is
> outstanding** and cannot be taken from this machine. See `STORE_CHECKLIST.md` §2.

---

## Scope reality

Four biomes with unique bosses is a **12–24 month solo project with art**. One polished biome with
one boss is a **shippable vertical slice in a few months**.

This plan is deliberately ordered so **Phases 1–7 produce a complete, shippable Biome 1** and you can
stop there. Biome 1 reaches shipping quality before Biome 2 begins. Do not open Thornwood because
Ashfall Village got boring to look at.

The three things this plan cannot solve for you, and which you must decide **before Phase 5**, are in
`§6` of the source brief: **art sourcing, animation count (~100+ clips for the full roster), and
scope.** Godot cannot generate models. That is the real cost of this project.
