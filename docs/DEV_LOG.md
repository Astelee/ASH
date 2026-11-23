# Ashfall — Development Log

One dated entry per phase. Three sections every time, and the last two are not optional:

1. **Built** — what shipped this phase.
2. **Deferred / suggested** — what I noticed but did **not** build, because it was out of phase
   (`CLAUDE.md §4.4`). This is where good ideas go to wait.
3. **Uncertain / deviations** — anything I am not confident about, and **every** place I deviated
   from the GDD or TECH spec, with the reason.

Newest entry at the top.

---

## 2026-08-15 — Orphan sweep: the bloodstain loop, hit feedback, and status effects

A follow-on audit for the same defect class the realism pass turned up: **code that was written,
tested, correct, and connected to nothing.** Five found, all closed.

The check that found them: for every script, does its `res://` path appear in any scene, does its
`class_name` appear in any other script, or is it an autoload? It is now
`tools/find_orphans.py`, wired into `scripts/lint.sh` as a gate step, because the unit suite
**cannot** catch this failure mode by construction — a well-tested orphan passes every test it has,
and every defect below was green in CI.

Deliberately, the check does not count references from `tests/`. A script reached only by its own
test is still unreachable in the game, and that distinction is exactly what found the last two:
`StatAllocation` and `LevelChunk` both looked referenced until test files were excluded.

### Built

- **`actors/npc/Bloodstain.tscn`** — the pickup. This one mattered: `GameState` had always tracked
  the dropped purse correctly, `LevelRoot._place_bloodstain()` had always been called on level
  entry, and `bloodstain.gd` had always been written — but no scene existed for `bloodstain_scene`
  to point at, so the export was null in every level and **the pickup never appeared in the world**.
  The whole Souls loop — die, lose the purse, walk back for it — was unclosable in practice. Wired
  into Ashfall Village and Cadwyn Arena.
- **`combat/hit_feedback.gd`** — drives `hit_flash`, `poise_break_glow` and `dissolve_amount` on all
  seven actors. Writes through `set_instance_shader_parameter`, never the material: the roster
  shares one `ShaderMaterial` to batch, so a material write would flash every enemy on screen when
  one got hit. Stops processing the moment there is nothing to animate, so an idle crowd costs
  nothing (`CLAUDE.md §3`).
- **`combat/status_tracker.gd`** plus `Combatant` integration and `DamagePacket.status` — the
  consumer `StatusEffect` never had. Build-up is a threshold, not damage-over-time: a Rot flask does
  nothing until the meter fills, which is what makes it a resource the player manages by retreating
  rather than a tax they cannot respond to. `data/status/status_rot.tres` authored and hung on the
  Crow-Mask Cultist via a new `EnemyData.inflicts`, so the path is exercised end to end.
- **`StatAllocation` wired**, the fifth orphan and the last unreachable Phase 7 screen. It opens on
  `EventBus.rested_at_wayshrine` rather than being placed in levels, so the Wayshrine never has to
  know a level-up screen exists (`CLAUDE.md §2`). Also given `PROCESS_MODE_ALWAYS` — it pauses the
  tree itself, so without that its own buttons went dead and the player would be stuck at a
  Wayshrine with no way to close it.
- **`tools/find_orphans.py`**, and a new `orphaned scripts` step in `scripts/lint.sh`.
  `LevelChunk` is the one allowed entry: a `@tool` authoring aid dragged into a scene by hand, so it
  is referenced by the levels a designer builds rather than by any shipped scene.
- **`tests/test_feedback_loop.gd`** (7 tests) and **`tests/test_status.gd`** (12 tests).
  203 tests / 1150 asserts total, up from 184 / 1099.

### Fixed

- **`HitFeedback.flash()` wrote full strength only on the next frame.** On any frame longer than
  `hit_flash_duration` — a hitch, or the 33 ms low-tier budget against a 120 ms flash — the decay
  ran first and landed on zero, dropping the flash entirely. It now writes 1.0 immediately; the one
  guaranteed lit frame is the whole point of the effect. Found by a test that failed for what looked
  like a test-harness reason and was not.
- **`Combatant.reset()` did not clear statuses**, so a respawned player would still be rotting from
  the hit that killed them. Caught while writing the test, before it could ship.
- **`StatusEffect`'s doc comment described a contract that did not exist** — it claimed
  `DamagePacket` had to be able to name one, and `DamagePacket` had no such field for three phases.
  Now true rather than rewritten away.

### Uncertain / deviations

- **`data/status/` is a new folder** under `data/`, which `CLAUDE.md §5` does not list. Consistent
  with the existing `tuning/ enemies/ items/ biomes/ stats/` split; flagging it because the layout
  section is meant to be exhaustive.
- **Status build-up has no HUD.** `Combatant.status_buildup_changed` carries the fraction ready for
  a bar and nothing draws it, so a player currently has no warning before rot triggers. That is a
  genuine playability gap, not a stylistic one.
- **Rot is the only authored effect**, and only the Cultist inflicts it. Bleed and the Bell-Bearer
  buff are still absent.
- **Phases 6–9 DEV_LOG entries backfilled** from commit history this session and labelled as such.
  Reconstructed from the commits, not re-derived from the code.
- **Still never run on an Android device.** Every number in this log is desktop.

### Deferred / suggested

- A build-up bar in `PlayerHud`, fed by `status_buildup_changed`.
- Bleed, plus a `StatusEffect` subclass for anything needing real `on_apply` behaviour rather than
  damage over time.
- An equivalent orphan check for `.tscn` and `.tres` files. `Bloodstain.tscn` did not exist at all,
  but an unreferenced *scene* would slip through today exactly as the scripts did.

---

## 2026-08-15 — Realism pass: PBR overhaul, and seven wiring defects closed

### Built

- **`surface/character_pbr.gdshader`** replaces `character_toon_pbr`, which is deleted. Full GGX +
  Schlick specular, ORM packing, a detail-normal layer at 9x tiling, baked AO on ambient only
  (`AO_LIGHT_AFFECT = 0.0`), and wrapped diffuse with a warm tint as a stand-in for the subsurface
  term the Mobile renderer does not have. `albedo_color`, `hit_flash`, `dissolve_amount` and
  `poise_break_glow` are now **instance** uniforms, so the whole roster shares one `ShaderMaterial`
  and still gets per-actor colour and a per-actor hit flash.
- **Actors wear the real material.** `CLAUDE.md §4.2` requires placeholders to carry the real shader;
  every capsule was wearing a `StandardMaterial3D` instead, so the character shader had never been on
  screen once. Player, five enemies and Ser Cadwyn now mount `mat_character_pbr` / `mat_enemy_pbr`,
  with each type's silhouette colour preserved as an instance parameter in its `.tscn`.
- **`terrain_triplanar`**: macro variation (low-frequency noise into albedo *and* roughness), a
  detail normal layer, slope auto-blend so cliffs expose rock without vertex painting, vertex-channel
  AO, and wetness now flattens normals as well as darkening albedo.
- **`foliage_wind`**: transmission is view-dependent (`pow(dot(V, -L), n)`) instead of an inverted
  `NdotL`, and diffuse is wrapped. The old version glowed from every angle.
- **Environment realism, driven from `BiomeMood`**: ACES tonemapping with per-biome exposure and
  white point, a `ProceduralSkyMaterial` sky, `fog_aerial_perspective` and `fog_sun_scatter`, and
  contrast/saturation/LUT moved onto `Environment.adjustment_*`. Ten new fields, all blended by
  `BiomeMood.blend`, all authored for the four biomes.
- **`ui/hud/ColorGrade.tscn`** — the fullscreen grade pass, which existed as a shader file and was in
  no scene. Two materials, one quad, picked by `QualityManager.allows_screen_texture()`.
- **`ui/hud/GameHud.tscn`** — `PlayerHud`, `PauseMenu` and `DeathScreen`, wired into all five
  playable scenes. `FootstepEmitter` plus its own `GroundRay` wired into `Player.tscn`.

### Fixed

Seven defects found by audit, all confirmed before changing anything:

1. `Settings.set_value` guard was `not has_method("get") or get(key) == null and not _has_property(key)`.
   `has_method("get")` is always true and `and` binds tighter than `or`, so the guard reduced to
   "is the value null" — an unknown key sailed through and a legitimately-null setting was rejected.
2. `Enemy.commit_range()` had two identical branches.
3. `PlayerHud` positioned the Embers readout with `float(safe.size.x > 0) * margin` — a boolean cast
   doing nothing. It now computes a real right-hand safe inset from the window size.
4. Settings were loaded at startup and never applied. `GameState._ready` now defers `Settings.apply`.
5. `AudioDirector._listener` was stored and never used, so 3D panning came from the camera 8 m back
   on Z. It now creates a real `AudioListener3D` and calls `make_current()`.
6. `BiomeMood.fog_height_min` was authored and blended but never applied; half of every fog profile
   was silently discarded.
7. `PlayerHud`, `PauseMenu`, `DeathScreen` and `FootstepEmitter` were in no scene at all — Phase 7
   and 8 deliverables that were written and never instantiated. So was the grade pass.

### Uncertain / deviations

- **Deviation from the original art direction.** The brief specified stylized toon shading; this is
  grounded realism, at the user's explicit request. `CLAUDE.md §4.1` is untouched — the project is
  still Mobile renderer, and no effect added here needs Forward+. `TECH.md §2` is updated to match.
- **Deviation: MID tier no longer enables glow.** Bloom allocates a mip chain of the whole
  framebuffer, measured at **16.0 MB of the 60 MB texture budget** on Ashfall Village. MID is the
  tier the budget is defined on. HIGH keeps it. `BiomeMood.glow_strength` is still authored per
  biome and simply has no effect below HIGH.
- **Deviation: chromatic aberration is HIGH tier only.** It is the one effect in the post chain that
  must read neighbouring pixels, and `hint_screen_texture` measured **+11.8 MB**. Below HIGH the quad
  mounts a `blend_mul` material that produces identical vignette, grain and pulse for zero memory.
  The three moods that author CA (Ossuary 0.35, Bastion 0.2, Thornwood 0.15) keep their values.
- **Measured, not estimated.** The three costs above were isolated by toggling each addition
  independently against `BudgetVillage.tscn` on a real GPU: base 53.8 MB, sky +5.7, glow +16.0,
  back buffer +11.8, total 87.3 against a 60 MB limit. Sky radiance dropped 128 → 32 (ambient comes
  from a flat colour on this renderer, so radiance only feeds specular). Final: Village 54.3 MB /
  34 draw calls, Arena 49.0 MB / 17 draw calls.
- **`hit_flash` still has no driver.** The uniform is now genuinely on screen and per-instance, and
  `CombatTuning.hit_flash_duration` exists, but nothing writes it yet. Listed below.
- **Phases 6–9 have no `DEV_LOG` entries.** `CLAUDE.md §6.5` requires one per phase and four are
  missing. Not backfilled here — flagging it rather than inventing history after the fact.
- **Still never run on an Android device.** Every number above is desktop. `docs/STORE_CHECKLIST.md`
  §2 remains the outstanding list.

### Deferred / suggested

- Drive `hit_flash` from the hitstop system onto the new instance uniform.
- Author real ORM and detail-normal textures; every material currently runs on `hint_default_white`,
  so the ORM and detail paths are wired but contributing nothing.
- A macro-noise texture for the terrain — same situation, the code path is live and the sampler is
  white.
- Backfill the four missing `DEV_LOG` entries from the commit history.

---

## 2026-08-15 — Phase 9: ship pass — budget gate, build pipeline, lifecycle tests

> Backfilled 2026-08-15 from commit `f8cdedc`. `CLAUDE.md §6.5` requires an entry per phase and this
> one was missed at the time. Reconstructed from that commit and its diff, not re-derived.

### Built

- **`tests/BudgetVillage.tscn` / `BudgetArena.tscn`** — budgets asserted with a **real** rendering
  driver. Headless would have been worthless: the dummy rasteriser reports zero for every render
  monitor, so a headless budget check passes a scene with ten thousand draw calls.
  Village 27 draws / 8,152 tris; Arena 10 / 7,008. Draw calls and triangles transfer to the device
  unchanged; frame time and VRAM do not, so frame time is reported and not enforced.
- **`scripts/build.sh`** — APK and AAB export. Runs both gates first and refuses to build on a red
  suite. The AAB path verifies 16 KB page alignment on every LOAD segment, because Play rejects
  0x1000-aligned uploads and a Gradle plugin or old NDK anywhere in the chain can silently undo
  Godot's alignment. Signing comes from environment variables, never a committed file.
- **`scripts/perf.sh`** — `gfxinfo` framestats parsing, with a `--thermal` mode sampling every 30 s
  for 20 minutes.
- **`tests/test_lifecycle.gd`** — pause/resume correctness and leak checks: that
  `NOTIFICATION_APPLICATION_PAUSED` writes a readable save, that twelve rapid autosaves still leave
  a loadable file, that a backup exists after the second write, and that audio voices and attack
  tokens are released rather than leaked.
- **`docs/STORE_CHECKLIST.md`** — ordered, blocking items marked.

### Uncertain / deviations

- **Phase 9 is not complete and cannot be from this machine.** Every on-device item is outstanding:
  60 FPS on mid tier, the 30 FPS low-tier floor, the thermal soak, fog-card depth read cost, touch
  latency against the parry window, 9 mm targets, camera framing, force-close correctness. The
  tooling to measure all of it exists; the measurements do not.

---

## 2026-08-15 — Phase 8: audio — bus layout, pooled voices, stems, ducking, footsteps

> Backfilled 2026-08-15 from commit `45faf9a`.

### Built

The mix, around three decisions:

- **The pool never grows.** 24 positional voices created once at ready and reused — `CLAUDE.md §3`
  forbids per-frame allocation and audio is the most frequent spawn in a fight. When every voice is
  busy a claim steals the lowest-priority, oldest voice, and **never** one of higher priority than
  itself. A footstep landing during a Gravewretch rattle simply does not play, which is the right
  failure: losing that tell to a puddle of grass sounds costs the player a life.
- **Gameplay signals are not set dressing.** Banks flagged `is_gameplay_signal` are exempt from
  distance falloff and occlusion entirely and sit at the top of the stealing order. The GDD requires
  the Gravewretch lunge to be survivable on audio alone and the Bell-Bearer bell to be audible
  before it is visible; neither survives being attenuated by a wall.
- **Ducking is a target, not an event.** 0.08 s attack, 0.35 s hold, 1.2 s release. Duck-on-trigger
  with a fixed release pumps audibly the moment two hits land close together. A riposte or parry
  ducks harder than an ordinary hit.

Also: a bus layout with reverb send (driven by `BiomeMood.reverb_wet`), muffle bus, SFX compressor
and Master limiter — layered stems plus a boss plus adds will clip, and clipping on a phone speaker
is indistinguishable from a broken file. `SoundBank` picks takes without repeating the last one,
with pitch and volume jitter. Five stems mixed by **gain** rather than started and stopped, so they
stay sample-locked; starting a stem on demand drifts it out of phase within a bar and turns a
layered score into a smear. Footsteps driven by **distance travelled**, not a timer, which desyncs
the moment the actor changes speed; surfaces tagged on the ground rather than the walker, so a new
surface needs no actor changes.

### Fixed

- `MoodDirector.snap_to()` applied a mood but never emitted `mood_changed`, so entering a level set
  the visuals and silently skipped every listener that only hears gradual transitions — which is the
  entire audio mix. Reverb and stems would have been wrong on every level entry.
- Added `AudioDirector.stop_all()` for scene transitions, where a footstep from the level you just
  left has no business finishing in the one you entered.

### Uncertain / deviations

- **No audio assets exist.** Every bank is empty until real sound is sourced. The tests assert the
  *policy* — which voice, which bus, which gain — because policy is what silently regresses.
  **Nothing has been heard.**

---

## 2026-08-15 — Phase 7 (partial): settings, localization, HUD, pause, death, stat allocation

> Backfilled 2026-08-15 from commit `ad9b6ef`.

### Built

- **Settings**, persisted to its own `ConfigFile` rather than through `SaveSystem`. Deliberate:
  settings must survive deleting a save, and a player who wipes a run should not lose their control
  layout and accessibility options with it. A plain class with a lazy singleton accessor, **not** a
  tenth autoload — `CLAUDE.md §2` sets the bar at "two unrelated systems need it and nothing in the
  tree can own it", and a settings blob is neither.
- **`ui/strings.csv`** — 64 keys, registered as a translation. Every user-facing string in the new
  UI goes through `tr()`. The tests check that required keys exist **and** that none is duplicated;
  a duplicate silently wins or loses by load order, which is the worst kind of localization bug
  because it only appears in one language.
- **`PlayerHud`** — health, stamina, flask, Embers. Sized in **millimetres** from screen DPI rather
  than pixels; a pixel-sized HUD shrinks on exactly the dense panels where it is already hardest to
  read. Flask charges are pips, because a two-thirds-full bar does not tell you whether that is one
  drink or two.
- **`PauseMenu`** — also the Android predictive-back target. `NOTIFICATION_WM_GO_BACK_REQUEST` opens
  it rather than killing the activity, which would otherwise close the game mid-fight and lose the
  run. Pausing autosaves.
- **`DeathScreen`** — listens on `EventBus.player_died` so it needs no wiring in any level.
  Deliberately does **not** pause the tree: the bloodstain drop and autosave happen before it
  appears, and pausing mid-write is how a save gets truncated.
- **`StatAllocation`**, deferred from Phase 3. Buying a level and spending the point are separate
  actions — Souls-likes merge them into one confirm, which means a misclick costs the level as well
  as the point. Here a level banks a point and you can hold three while deciding.

### Uncertain / deviations

- **Not done**: the settings *screen* itself (the model and persistence are complete and tested; the
  sliders are not), the main menu, loading screens, the drag-to-move control layout editor (offsets
  persist and round-trip; the dragging UI does not exist), and the colourblind palettes are an enum
  with no LUTs behind them — the same blocked LUT pipeline as Phase 4.
- **None of these screens was instantiated in any scene.** Found and fixed 2026-08-15 — see the
  realism-pass entry. They were correct, tested code that had never once been on screen.

---

## 2026-08-14 — Phase 6: enemy roster and Ser Cadwyn the Rusted

> Backfilled 2026-08-15 from commit `e489f90`.

### Built

All five enemies plus the first boss. The roster is data — adding a variant is a `.tres` per
`CLAUDE.md §1` — but four needed genuinely new behaviour, and that is where the work went:

- **Crow-Mask Cultist** — throws rot flasks on a ballistic arc **solved for the actual distance**,
  so a flask thrown at 4 m and one at 12 m both land instead of the near one sailing overhead.
  Retreats when closed on: a ranged enemy that stands and fights once cornered is just a worse melee
  enemy, and giving ground is what makes closing on it the correct answer.
- **Warden** — a shield absorbing 80 % of **frontal** damage only, dropped during the attack windup.
  Both halves matter: flanking has to work or "parry or flank" is a lie, and a Warden that guarded
  while swinging would have no opening at all.
- **Gravewretch** — a pounce with a 0.5 s dead-still telegraph, carried on
  `EventBus.enemy_telegraphed`. In the shipped game that tell is audio (Phase 8); the timing window
  exists now so hooking the sound up later changes nothing about the behaviour.
- **Bell-Bearer** — an aura buffing nearby allies, written as a node on the Bearer rather than a
  status effect on its allies, so the buff vanishes the instant it dies. Otherwise the reason to
  prioritise it disappears.
- **Ser Cadwyn** — 1450 HP, two phases at the GDD 55 % threshold, a phase-2 rust slam that is a
  guaranteed poise break, two Husk adds on transition, a fog gate that seals on entry and opens
  permanently on death, and an HP bar marking the phase thresholds so the change is visible coming.

### Uncertain / deviations

- **`StatusEffect` was never wired to anything.** Its own doc comment claims `DamagePacket` has to
  be able to name one; `DamagePacket` has no such field. The Bell-Bearer aura deliberately avoided
  it (above), which left the class with no consumer at all. Noted 2026-08-15.

---

## 2026-08-13 - Phase 5 (partial): level-assembly systems, and the Phase 3 gaps closed

### Built

- **`LevelChunk`** - hand-authored pieces with entry/exit connectors. Set `snap_to` in the inspector
  and the chunk moves so its entry lands on that chunk's exit. Runs as `@tool`, so the snap happens
  while authoring. Position only: rotating a chunk would break the 2.5D action plane, and a chunk
  that needs rotating is a different chunk.
- **`EncounterVolume`** - a group that spawns together, shares its own `AttackScheduler`, and
  respawns on rest. Spawning is deferred until the player is near, so twenty encounters do not cost
  twenty groups of AI on load. Enemies are freed and re-instanced on respawn rather than reset -- an
  enemy mid-attack holding a token is a tangle of state, and a fresh instance is provably correct.
- **`ParallaxLane`** - depth-lane drift. True perspective alone barely moves a wall 40 m back at a
  42-degree FOV, so each lane copies a fraction of camera travel. Vertical drift is off by default:
  it makes the horizon bob during jumps, which reads as a loose world.
- **`ShortcutGate`** - one-way becomes two-way, stored as a world flag, so it survives death and the
  save file. The whole Souls-like shortcut idea in one node.
- **`PropScatter`** (`tools/`) - deterministic MultiMesh scattering with an inspector "Rescatter"
  button. Writes `INSTANCE_CUSTOM.x`, which is the per-instance phase both `foliage_wind` and
  `emissive_flicker` read.
- **`Enemy.bind_scheduler()`** - an encounter injects its own token pool; a hand-placed enemy falls
  back to the level director; with neither it attacks freely, so a lone enemy still runs on F6.

### Two Phase 3 gaps closed

Both were deferred with "needs Phase 5 level tooling", and both are now done:

1. **Enemy respawn on rest.** `EncounterVolume` listens on `EventBus.rested_at_wayshrine`. Bosses
   recorded in `bosses_defeated` and encounters marked `clear_once` never come back; patrols always
   do. `test_level_systems.gd` asserts the two records stay separate -- conflating them would
   resurrect a boss.
2. **Bloodstain placement.** `LevelRoot` instantiates the pending stain if it belongs to this level.
   A stain dropped elsewhere stays there: there is only ever one, and walking into a different area
   must not quietly relocate it.

### Verified

Lint green. **113 tests, 356 asserts.** All nine shaders compile.

### Deferred / suggested

- **Ashfall Village itself is not built.** The systems to assemble it exist and are tested; the level
  is content, and content wants the art decisions from the source brief's section 6 rather than more
  greybox. This is the honest boundary: Phase 5's *tooling* is done, its *level* is not.
- **No `.tscn` chunk library.** `LevelChunk` works, but there are no authored chunks to drag
  together. First chunks should come with the first real art.
- **`LightmapGI` baking.** Nothing is baked. Needs real static geometry and UV2 unwraps first.

### Uncertain / deviations

1. **Acceptance criterion 1 is provable, 2 and 3 are not yet.** "Build a new area by dragging chunks
   together without writing code" is asserted in the suite. "Village runs at 60 FPS within budgets"
   and "the shortcut makes the second traversal materially shorter" both need the village to exist.
2. **`PropScatter` is a `@tool` node, not an editor plugin.** The brief asked for a plugin in
   `tools/`. A node with an inspector button does the same job with far less surface area, and it
   works at runtime too. Flagging the deviation; a plugin can wrap it later if the workflow wants one.
3. **Nothing here has been seen on screen or on a device.** Unchanged, and now five phases deep.

---

## 2026-08-13 - Phase 4: fog cards, mood triggers, material library, showcase

### Built

- **`FogCardField`** - a whole fog volume in **one draw call**. A hundred individual quads would eat
  most of the 130-call budget on atmosphere alone. Card count is the product of the authored count,
  the tier fraction, and the mood density: the tier decides what the device affords, the mood decides
  what the place should feel like. Transforms are scattered once and kept, so a tier change re-slices
  the same field instead of re-randomising it - fog must not visibly rearrange when the resolution
  drops mid-fight.
- **`LevelRoot`** - the one place binding the level environment, sun, and camera to `MoodDirector`,
  and unbinding on exit so a freed `Environment` is never written to after a scene change. **It also
  closes the shadow gap**: `QualityManager` writes shadow size to `ProjectSettings`, which never
  reaches an already-instantiated light, so the level applies it to its own sun.
- **`MoodTrigger`** - names a mood and a duration, hands both to the director, holds no effect logic
  of its own. The moment a trigger tweaks fog directly, "all mood is one call" is gone.
- **Material library** - seven authored `ShaderMaterial` resources in `art/materials/`.
- **`levels/test/mood_showcase.tscn`** - walk right from the village into the Ossuary and back, with
  a fog field either side of the threshold. Runs clean on a real renderer.
- `PlayerCamera.set_fov()`, so the rig stays the only thing touching its own `Camera3D`.

### Verified

Lint green. 100 tests, 337 asserts. All nine shaders compile. The showcase runs with a real
rendering driver, no shader or script errors.

### Deferred / suggested

- **God-ray placement.** Shader and material exist; nothing instantiates cones into a level. Wants
  the same treatment `FogCardField` got, and belongs with Phase 5 level tooling.
- **The LUT pipeline.** `grade_and_grain` cross-fades two LUT textures and `BiomeMood` carries the
  slot, but **no LUT textures exist and nothing mounts the post-process ColorRect**. Largest
  remaining hole in Phase 4, and it needs authored art rather than code.
- **Placeholder capsules still wear `StandardMaterial3D`.** `mat_character_toon` exists but is not
  assigned - best swapped alongside the first real models.

### Uncertain / deviations

1. **Look and performance cannot be self-assessed.** The first acceptance criterion is a judgement
   call and the second needs the device. Everything here is verified as correct and compiling, not as
   good. The showcase exists so that judgement takes about thirty seconds.
2. **The fog-card depth read remains unmeasured** - still the most likely place this project loses
   its frame budget, and now there is a scene that exercises it.
3. **Fog density mapping is a guess.** `FogCardField` maps `fog_density` to card alpha as
   `density * 40`, so one authored knob drives both depth fog and card opacity. The factor was picked
   to make the Ossuary read thick and the Village light; it wants eyes on it.

---

## 2026-08-13 - Phase 4 (cont.): all nine shaders, and a real-GPU compile gate

### Built

- **The six remaining shaders**: `foliage_wind` (world-seeded sway, per-instance phase from
  `INSTANCE_CUSTOM`, backface translucency, alpha_scissor only), `terrain_triplanar` (three-axis
  projection, vertex-colour A/B blend, wetness), `emissive_flicker` (two-band noise evaluated
  per-instance in the shader), `god_ray_cone` (cull_front, three independent fades),
  `water_flow` (flowmap phase cross-fade, shoreline depth fade, refraction gated behind a uniform),
  `dissolve_teleport` (world-axis burn, separate from the character death dissolve on purpose).
- **`tests/ShaderCompileCheck.tscn`** - draws every shader once with a real rendering driver.
- **`scripts/test.sh` gains a shader-compile stage**, skippable with `SKIP_SHADER_CHECK=1`.
- Shader globals moved into `project.godot` under `[shader_globals]`.

### Verified

Lint green. 100 tests, 337 asserts. **All nine shaders compile on a real GPU with zero errors.**

### The compile gate earned its place immediately

The headless suite reported a clean pass on shaders that **could not compile at all**:

1. **`DEPTH_TEXTURE` was removed in Godot 4.7.** `fog_card` and `god_ray_cone` both used it, and both
   failed hard on a real renderer. It is now a `hint_depth_texture` uniform. `--headless` uses a dummy
   rasteriser that never compiles anything, so the unit suite had no way to see this -- it could only
   prove the files parse as `Shader` resources.
2. **`global_shader_parameter_add/get` are editor-only** and warn loudly at runtime. `MoodDirector`
   was calling both on ready. The globals are now declared in `project.godot` and the director only
   writes them.

This is exactly the gap called out in the previous entry as "open the editor before trusting any of
this". Rather than leave it as advice, it is now a gate stage that fails the build.

### Deferred / suggested

- **The fog-card MultiMesh system, the god-ray placement system, the LUT pipeline, and the showcase
  scene** are still not built. The shaders exist; nothing instantiates them into a level yet.
- **No `.tres` materials** in `art/materials/` - each shader still needs an authored `ShaderMaterial`
  per biome.
- **`QualityManager` shadow settings** still write through `ProjectSettings` and do not reach
  instantiated lights. Unchanged from the previous entry.

### Uncertain / deviations

1. **Compiled on a desktop GPU, not on Adreno or Mali.** Mobile drivers are stricter about precision
   qualifiers and loop bounds, and the Mobile renderer path differs from what a desktop Vulkan driver
   accepts. A clean desktop compile is necessary, not sufficient.
2. **The fog-card depth read is still unmeasured.** It compiles; what it costs on a tile-based GPU is
   the open question, and it remains the most likely place this project loses its frame budget.
3. **`terrain_triplanar`'s header corrects the Phase 0 spec.** Triplanar removes the need for a UV1
   unwrap only -- `LightmapGI` still requires UV2 on every static mesh. The original claim that it
   avoided unwrapping altogether was wrong, and the shader says so where someone will read it.

---

## 2026-08-13 - Phase 4 (partial): MoodDirector, QualityManager, first three shaders

### Built

- **`BiomeMood`** - every atmosphere parameter in one Resource: fog, light, grade, grain, wind,
  camera FOV, reverb, stem mask, particles. `BiomeMood.blend()` is a **static pure function**, so the
  transition is testable without a scene tree.
- **`MoodDirector`** - one call, one curve, everything at once. Interrupting a transition blends from
  where it currently *is* rather than from where it started, so walking back out of a trigger volume
  halfway does not pop. Writes `rim_color` and `wind_strength` as **global** shader parameters, which
  is one write per frame for a whole biome's worth of materials instead of a per-material loop.
- **Four authored moods** - `mood_village`, `mood_thornwood`, `mood_ossuary`, `mood_bastion`, exactly
  the `TECH.md` table.
- **`QualityManager`** in full - the three-tier table, dynamic resolution with asymmetric
  drop/recover, the `SCALE_FLOOR`, the boss-telegraph `hold_resolution` flag, and a conservative
  `tier_for_frame_ms()` for auto-detect.
- **Three shaders**: `character_toon_pbr` (banded diffuse, unquantized specular, hit flash, dissolve,
  poise glow), `fog_card` (Y-billboard, dual scrolling noise, soft-particle depth fade),
  `grade_and_grain` (LUT cross-fade, vignette, aberration, eerie pulse, grain - one pass).
- 100 tests, 325 asserts.

### Deferred / suggested

- **Six shaders remain**: `foliage_wind`, `terrain_triplanar`, `emissive_flicker`, `god_ray_cone`,
  `water_flow`, `dissolve_teleport`. `test_mood.gd` enumerates all nine and **prints the missing
  list** rather than quietly testing only what exists.
- **The fog-card MultiMesh system, the god-ray system, the LUT pipeline, and the showcase scene**
  are not built. Phase 4's acceptance criteria cannot be met without them.

### Uncertain / deviations

1. **Not a single shader has been compiled by a GPU.** `--headless` uses a dummy rasteriser, so the
   suite proves the files parse as `Shader` resources and nothing more. Syntax errors in a `light()`
   function would not surface until the project is opened with a real renderer. **Open the editor
   before trusting any of this.**
2. **The `fog_card` depth read is the risk flagged in Phase 0, now written.** `soft_particles` is a
   uniform rather than a hardcoded branch precisely so it can be switched off per tier if the device
   says the tile-buffer resolve is too expensive. That decision needs a measurement, and the fallback
   is a visibly worse-looking game - so do not reach for it on suspicion.
3. **`QualityManager.apply()` writes the shadow size via `ProjectSettings`**, which does not affect
   already-instantiated lights. Shadow size and split count need to be pushed onto the level's
   `DirectionalLight3D` through `MoodDirector.bind_world`. Known gap, not yet wired.
4. **Phase 4 is roughly a third done.** Reporting it as partial rather than letting three good
   shaders stand in for nine.

---

## 2026-08-13 - Phase 3: Progression & persistence (partial)

### Built

- **`Progression`** - the cost curve as pure static functions, one place in the project.
  `tests/test_progression.gd` *regenerates* the GDD's published table from the formula rather than
  hardcoding it, so the code and the design document cannot silently diverge in either direction.
- **`GameState`** - level, stats, Embers, flask, Ash Shards, world flags, boss defeats, bloodstain.
  Plain `to_dict` / `from_dict`; no Resources or node references cross the boundary.
- **`SaveMigrations`** - schema at **v2**, with a real v1 -> v2 migration. Pure Dictionary functions,
  no file access, so a failed migration cannot corrupt anything on disk.
- **`SaveSystem`** - gzip JSON, SHA-256 envelope, temp-file-then-rename, `.bak` rotation, backup
  fallback on checksum failure, autosave on rest / death / `NOTIFICATION_APPLICATION_PAUSED`.
- **The Ashen Flask** - `PlayerFlaskState`, 1.10 s committed, heal at 0.55 s, charge spent up front,
  Ember-Bound potency scaling, Ash Shard capacity.
- **Death loop** - `EventBus.player_died` -> bloodstain; `Bloodstain` reclaims on touch; dying again
  destroys the first stain.
- **`Wayshrine`** - rest, refill, respawn point, autosave.
- **Ember credit** - `EventBus.enemy_died` -> `GameState`, so an enemy never calls the run directly.

### Verified

Lint green. **85 tests, 272 asserts, all passing.** Both spec anchors on the curve hold exactly
(1 -> 2 = 90, 30 -> 31 = 16,658), the published cost and cumulative tables regenerate, and the
Biome 1 economy solve lands the player at L12 from a full clear.

### Deferred / suggested

- **Stat allocation UI.** `GameState.allocate_point()` is implemented and tested; the *screen* is
  not. Phase 7 owns UI and building a throwaway now would be building it twice.
- **Enemy respawn on rest.** `EventBus.rested_at_wayshrine` is emitted and levels can listen, but no
  level implements it - chunk-based level assembly is Phase 5, and the combat gym has no spawner.
- **Bloodstain placement on load.** `GameState` records where it is; nothing yet instantiates the
  scene into a level on entry. Also Phase 5.
- **`actors/npc/`** now holds Wayshrine and Bloodstain, which are interactables rather than NPCs.
  Suggest a `levels/props/` folder when Phase 5 formalises level content.

### Uncertain / deviations

1. **The checksum covers the payload *bytes*, not a nested object [deviation].** `TECH.md` showed
   `payload` as a nested JSON object. Checksumming it that way cannot work: JSON has one number
   type, so an integer 7 parses back as 7.0 and re-serialising never reproduces the original text -
   **every load fails its own checksum.** The suite caught this on the first run. The payload is now
   an embedded JSON string and the checksum covers exactly those bytes. `TECH.md` updated to match.
2. **Acceptance criterion 5 (force-close mid-run, reopen correct) is unverified end-to-end.** The
   save round-trip through a real file passes headless and the pause notification is wired, but
   nobody has actually killed the app on a device. Same gap as Phases 1 and 2.
3. **Phase 3 is partial, not complete.** The systems are done and tested; the Wayshrine UI and enemy
   respawn are not. Reporting it honestly rather than marking the phase green on the systems alone.
4. **v1 -> v2 is a genuine migration, not a demo.** v1 is the schema published in Phase 0; the flask
   and gear were designed in Phase 0a, after it. A v1 save arrives with a **full** flask - reloading
   into a run with no healing would be a silent unwinnable state rather than an obvious bug.

---

## 2026-08-13 — Phase 2: Combat core

### Built

- **Combat vocabulary** (`combat/`): `DamagePacket`, `Hitbox`, `Hurtbox`, `AttackMove`,
  `StatusEffect` base, `Combatant`, `AttackScheduler`, `EncounterDirector`. Player and enemy scenes
  know only these — neither can name the other's scene.
- **`Damage`** (`systems/damage.gd`) — the whole formula as pure static functions. No nodes, so every
  number the combat system produces is reproducible headless from data.
- **`Combatant`** — health, stamina, poise, and per-actor hitstop, composed into both the player and
  every enemy so one implementation of the rules serves both.
- **Data model**: `CombatTuning`, `WeaponData` (letter-grade scaling vector), `ShieldData`,
  `EnemyData`, `StatBlock`, plus the authored `.tres` — Ashen Longsword, Wooden Kite, six attack
  moves, Husk stats and data.
- **Player combat**: 3-hit light chain driven by index off one state, chargeable heavy, dodge with
  i-frames, block with the shield model, parry, stagger, death.
- **Husk** — the full AI state machine, entirely `.tres`-driven.
- **Attack tokens** — `EncounterDirector` owns one scheduler per level.
- **Pooled damage numbers**, pre-allocated, listening on `EventBus`.
- **GUT 9.6.1** vendored; 41 unit tests, 78 asserts. `tests/CombatCheck.tscn` for integration.
- **Named collision layers** (flagged as owed since Phase 0).

### Verified

Lint green. Test gate green: 41/41 GUT, MovementCheck 10/10, CombatCheck 12/12. Damage through the
full scene-tree path lands on **43.1855** — the GDD's worked example to four decimals. Riposte
**95.0081** against a predicted 95.0129. The token cap held at exactly 2 across 900 frames of live
three-Husk AI, and the test asserts the cap was *reached*, so it cannot pass by never being stressed.

### Deferred / suggested

- **Hit flash** — needs `character_toon_pbr.hit_flash`, which does not exist until Phase 4. The
  hitstop it accompanies is implemented. Logged in `ASSET_MANIFEST.md` as blocked, not forgotten.
- **Concrete status effects** — base class only, per the phase boundary. Rot and bleed arrive in
  Phase 6 with the enemies that inflict them.
- **`data/moves/`** is a new folder under `data/`, not in the `CLAUDE.md §5` layout. Attack moves are
  data and had nowhere else to live. Suggest folding it into the documented layout.
- **Enemy hurtbox `monitorable` is toggled off on death** rather than the corpse dissolving. Phase 4.

### Uncertain / deviations

1. **`Player.health` and `max_health` became methods.** The `Combatant` owns the pools now. This
   silently broke `tests/movement_check.gd`, which was assigning to what is now a method — caught
   only because the test gate hung rather than failed. **The lesson is the gate design, not the
   rename:** a suite that hangs takes the run down with no output. `scripts/test.sh` now wraps every
   invocation in `timeout` with stdin closed, and reports a timeout distinctly from a failure.
2. **Sprint is a held dodge, and the roll now fires on button *release*.** Souls-accurate, and the
   only way one button serves both, but it adds up to 0.18 s of latency before a roll starts. Worth
   feeling on the device before accepting; the alternative is a separate sprint action the spec's
   input map does not have.
3. **`parry_window_touch = 0.24` is still an estimate.** The instrumentation described in
   `TECH.md §6` cannot run without a device. Acceptance criterion 5 is **unmet**.
4. **Enemy attack selection is `randi()` over the moveset.** Fine for a one-move Husk; the Warden and
   Cadwyn need weighted, range-aware selection. Phase 6.
5. **`Combatant` no longer self-initialises when its stats come from a parent.** Children are ready
   before parents in Godot, so an enemy configuring its combatant in `_ready` always ran too late —
   `configure()` is now explicit. The old code errored on every correctly-built enemy.
6. **The attack-token score is proximity plus a facing bonus.** It satisfies "best approach angle,
   not nearest", but the weighting is a guess and will want tuning once there are enemies with
   genuinely different ranges.
7. **Not verified on device.** Same gap as Phase 1, now larger: combat timing, touch latency, and
   frame cost under three active enemies are all unmeasured on real hardware.

---

## 2026-08-13 — Phase 1: Movement, camera, controls, greybox

### Built

- **`StateMachine` / `State`** (`systems/`). Actor-driven rather than self-driving: a child node
  ticks *after* its parent, so a machine running its own `_physics_process` would set velocity only
  after the actor had already moved on it, costing a frame of input latency every frame.
- **`MovementTuning` / `CameraTuning`** + `tuning_movement.tres` / `tuning_camera.tres`. Every value
  in `GDD.md §5` and `§4`, plus derived getters (`jump_velocity`, `gravity_for`, `accel_for`,
  `fall_damage_for`). No movement literal exists in any script.
- **`Player`** (`CharacterBody3D`) with six states — `Idle`, `Run`, `Jump`, `Fall`, `Land`,
  `LedgeGrab` — plus coyote time, jump buffer, asymmetric gravity, terminal velocity, ledge
  detection by paired raycasts, landing recovery, and fall damage. Pinned to Z = 0 each frame.
- **`PlayerCamera`** — dead zone applied to the *focus point* rather than the camera, look-ahead,
  asymmetric damping via frame-rate-independent exponential approach, vertical tracking frozen while
  airborne.
- **`InputRouter`** — device detection, analog axis merging, and touch buttons that feed synthetic
  `InputEventAction`s through `Input.parse_input_event`, so press/just-pressed semantics come from
  the engine and are identical across touch, key, and pad.
- **`DynamicJoystick`, `TouchButton`, `TouchControls`** — dynamic-origin stick, raw multi-touch
  handling with per-finger index tracking, safe-area insets, and physically-sized button layout.
- **`levels/test/movement_gym.tscn`** — 2.0 m walk gap, 3.5 m sprint gap, 5.5 m impossible gap with
  a recovery ramp, 1.5 m / 3.0 m steps, a 5.6 m ledge-grab wall, 40° / 46° / 55° slopes, and an
  11 m fall-damage drop. Every measurement derived from the tuning values it tests.
- **`DebugOverlay`** — FPS, frame time split, draw calls and triangles against budget, texture and
  video memory, tier, render scale, and live player state. F3 or a three-finger tap.
- **`QualityManager`** — frame cap only, as scoped.
- **`scripts/test.sh`** + `tests/MovementCheck.tscn` (see below).

### Verified

`./scripts/lint.sh` and `./scripts/test.sh` both exit 0. Ten assertions pass, including apex height
2.2012 m against a 2.2 m target, coyote window 0.1167 s against 0.12, and fall damage 40.0 HP for an
11 m drop.

### Deferred / suggested

- **Sprint has no input action.** The spec's map has ten actions and none of them is sprint, yet the
  movement table has a 6.0 m/s sprint speed. Implemented as **hold dodge** — the genre convention,
  and it leaves a tap free for the roll in Phase 2. `sprint_hold_threshold` is 0.18 s.
- **Haptics** are specified for `InputRouter` but Phase 1 has no parry, poise break, or level-up to
  fire them. Not written rather than written and unused.
- **Collision layer names** still not defined (flagged in Phase 0). Player is on layer 2, world on
  layer 1, hardcoded in the scene. Phase 2 should name them before hitboxes multiply.
- **`AnimNames` constants** not created — Phase 1 has no `AnimationPlayer`, and a constants file
  naming clips that do not exist would be a lie in a contract file.

### Uncertain / deviations

1. **Jump velocity is integrator-corrected — `9.8387` → `10.0220` m/s [deviation].** The textbook
   value is for continuous motion; we integrate discretely at 60 Hz with gravity applied before the
   move, which caps the real apex at **2.118 m** instead of 2.2. Adding half a step of gravity makes
   each step travel at its midpoint velocity, exact for constant acceleration. Documented in
   `GDD.md §5`. **This is the single most valuable thing the phase produced** — a 3.7 % shortfall is
   invisible on screen and would have been diagnosed months later as "the jump feels slightly off."
2. **Camera Z +12.5 → +8.0** — applied as agreed. Player now reads at 29.3 % of screen height.
   Unverified on a real panel.
3. **Joystick radius expressed in millimetres (8.9 mm), not the spec's 140 px [deviation].** 140 px
   is ~8.9 mm only on the 400 dpi target device; on a denser panel a pixel radius shrinks the stick
   physically. Every other touch measurement in `TECH.md §6` is already physical, so this matches.
4. **`class_name VirtualJoystick` collides with a native Godot 4.7 class** — renamed
   `DynamicJoystick`. Worth knowing that 4.7 has grown built-ins in this space.
5. **`scripts/test.sh` runs an interim harness, not GUT.** Phase 0 deferred both to Phase 2, but
   Phase 1's acceptance criteria are numeric and unfalsifiable by eye. The script's contract
   (headless, exit code) is designed so Phase 2 swaps the body for GUT in one line.
6. **The lint gate's engine step was wrong and is now fixed.** Per-file `--check-only` compiles
   without project context, so every autoload reference reported "Identifier not found". Replaced
   with a full project import, which validates scripts as the game actually loads them — and which
   is what caught the shadowed parameter, the native-class collision, and the unresolved node-path
   exports.
7. **Node-path exports need `node_paths=PackedStringArray(...)` in the `.tscn` node header.**
   Without it Godot stores a literal `NodePath` and every wired reference silently arrives null.
   Cost an hour; recorded here so it costs nothing next time.
8. **Not verified on device.** No Android hardware attached, so acceptance criteria 1 (60 FPS on
   device) and 4 (9 mm touch targets on a real panel) are **unmet**. Everything else passes
   headless. The touch layer in particular has never received a real finger.
9. **The player capsule wears a plain `StandardMaterial3D`, not `character_toon_pbr`**, which does
   not exist until Phase 4 — the one place Phase 1 misses the placeholder rule in `CLAUDE.md §4.2`.

---

## 2026-08-13 — Phase 0a: Progression curve, and the five open questions closed

Follow-up to the Phase 0 entry below. All six open questions from the Phase 0 review are now
resolved. Five of the six were mine to call; the first was yours.

### 1. Level cost curve → **exponent 1.535** *(your call)*

`cost(level) = floor(90 × level^1.535)`. Both of the spec's anchors now hold: **1→2 = 90** exactly
and **30→31 = 16,658** ≈ "17,000". The full table through L31 is in `GDD.md §7.2`, generated rather
than hand-typed — `tests/test_progression.gd` regenerates and asserts it in Phase 3.

You also asked for a **fairly known setup**, so the curve is now documented against the genre rather
than floating free. Six conventions are stated explicitly in `GDD.md §7.2`, the load-bearing one
being **cost depends only on total character level, never on which stat you buy** — the defining
FromSoft rule, and the reason soft caps have to exist (decision 2).

On shape: DS3 and Elden Ring use a cubic
([`0.02x³ + 3.06x² + 105.6x − 895`](https://darksouls3.wiki.fextralife.com/Level) from SL 13), but
those games run to SL 802 / RL 713. **Ashfall's useful range ends near L40.** A cubic over 40 levels
makes the last five cost more than everything before them, which on a phone reads as a wall. 1.535
reproduces the same *shape* over a much shorter climb — a per-quartile comparison table is in the
GDD. Half the total spend to L40 still happens after L30.

**This exposed a real problem and fixed it.** At the drop values I invented in Phase 0, reaching L30
cost **4,197 Husks** — the curve and the economy had never been checked against each other. Solved
backwards in the new `GDD.md §7.2b`: drops are now Husk 120 / Gravewretch 60 / Crow-Mask 175 /
Warden 400 / Bell-Bearer 900 / Cadwyn 4,500, so one full clear of Ashfall Village pays **20,025** and
lands the player at **L12**, with L15 costing 0.7 extra laps and L25 costing 6.3 — the curve
correctly saying "go to the next area." Biome drop multipliers ×1.0 / ×2.4 / ×5.5 / ×12.0 carry it
forward. **Enemy Ember values are no longer free parameters**; changing one means re-running the
solve.

### 2. Stat soft caps → **30 across the board**

Genre puts soft caps at 40–60, but those games hand out hundreds of levels. L40 yields 47 points
here, so 30 preserves the felt shape (most benefit in the first two-thirds, specialising beats
spreading) and is what makes the "cost ignores which stat" rule safe from single-stat dominance.

### 3. Healing → **the Ashen Flask** (`GDD.md §7.7`)

The spec had **no healing resource at all**, which a Souls-like cannot function without — the whole
"push one more room or walk back" loop hangs off a finite, checkpoint-refilled heal. 3 charges → 8,
90 HP base scaling with Ember-Bound, refilled at Wayshrines.

The number that matters: **1.10 s committed drink, heal applied at 0.55 s.** Mid-animation, not on
the first frame — that is what makes healing a decision rather than a reflex. Charges come from
found **Ash Shards** (level-design pacing), potency from Ember-Bound, base heal from Embers at a
Wayshrine — so it competes with levelling and needs no second currency.

### 4. Parry on touch → **device-dependent window, and an instruction to go measure it**

0.18 s on gamepad/keyboard, **0.24 s on touch**. Android touch-to-photon latency of 60–100 ms would
otherwise leave a touch player ~80 ms of real budget on a mechanic the Warden is *designed* to
require.

**0.24 s is a guess and is labelled as one.** `TECH.md §6` now specifies the Phase 2 instrumentation:
log touch-arrival → rendered-response over ≥ 200 real combat inputs at each quality tier, then set
`parry_window_touch = 0.18 + p90(latency)` and record it here. If the measurement pushes the window
past ~0.30 s, the parry has stopped being a precision mechanic and the Warden needs redesigning —
that is a design outcome to surface, not a number to quietly inflate.

### 5. Camera → **Z +12.5 → +8.0**, FOV unchanged at 42

At +12.5 the frame is 9.6 m tall: 21.3 m of level width on a 20:9 phone, player at **19 %** of screen
height (~1.4 cm on a 6.5" panel). A 0.65 s Husk wind-up is not readable at that size, and
readability is Pillar 1. At +8.0 the player is **29.3 %**, in the normal band for the genre.

Pulled the camera in rather than narrowing the FOV **because it also increases parallax** — lane
separation grows as the camera approaches the action plane, so this buys depth as well as
readability. FOV stays `MoodDirector`-drivable (34 crypt / 42 default / 50 arena); camera Z does not,
since changing distance mid-fight reads as the world moving. Both in `tuning_camera.tres`; verify on
the phone in Phase 1.

### 6. Weapon scaling → **a sum across all five stats**

`scale_bonus = Σ weapon.scaling[stat] × attacker.stat / 40.0`. The spec's `weapon.scaling[stat]`
implied one stat per weapon, but its own stat descriptions imply hybrids. A coefficient vector is
strictly more general — a single-stat weapon has zeros elsewhere, the worked example is unchanged,
and quality builds become possible at zero cost. Grades E/D/C/B/A/S map to 0.10 / 0.25 / 0.40 / 0.55
/ 0.75 / 1.00, so an S weapon at stat 40 doubles its base.

### 7. Block → **shield absorption + stability**, not double mitigation

The spec's "absorbs `100 × mitigation%`" reused the defender's own `defense`, applying armour
mitigation **twice** and scaling blocking off the wrong stat. Replaced with the two-number shield
model in `GDD.md §6.1b`: absorption is a property of the shield alone; **stability** —
`clamp(shield.stability_base + might × 0.006, 0, 0.70)` — governs stamina cost and is where **Might**
pays off, exactly as the stat's own description promises. Capped at 0.70 so blocking is never free.

This added a **shield gear slot**, which the block and parry mechanics required but the spec's gear
table never listed.

### Still uncertain

- The Ember economy assumes a village census of ~108 enemies. That number is invented and does not
  become real until Phase 5. If the level ends up half that size, drops or the census change — the
  solve is in `scratchpad/curve2.py` logic and should be re-run, not eyeballed.
- Every timing value in decision 4 remains unvalidated until it runs on hardware.
- Nothing here has been opened in Godot yet. See item 10 in the Phase 0 entry.

---

## 2026-08-13 — Phase 0: Foundations

### Built

- `project.godot` — Mobile renderer, 1920×1080 viewport, `viewport`/`expand` stretch,
  `sensor_landscape`, vsync on, ETC2/ASTC import, 2× MSAA, bilinear 3D scaling, 2048 directional
  shadow, gravity 22.0. All ten input actions bound to **keyboard + gamepad** for desktop testing.
- Nine autoload stubs in `systems/`, each documenting its contract and the phase that fills it in.
- `systems/log.gd` — `Log.debug/info/warn/error`, build-flag gated. Exists now so that no phase ever
  has an excuse to use `print()`.
- Folder skeleton with `.gdkeep`, `.gitignore`, `.editorconfig`, `scripts/lint.sh`.
- `README.md`, `CLAUDE.md`, `docs/GDD.md`, `docs/TECH.md`, `docs/PLAN.md`, `docs/ANIMATIONS.md`,
  `docs/ASSET_MANIFEST.md`, this file.
- Git repository initialized.

**No gameplay code, no scenes, no art.** As specified.

### Deferred / suggested

- **`scripts/test.sh` and GUT** — the brief's Phase 0 deliverable list names only `lint.sh`. GUT is a
  vendored addon and the first tests do not exist until Phase 2. Suggest adding both at the *start*
  of Phase 2 rather than carrying a dead script.
- **`scripts/build.sh` / `scripts/perf.sh`** — specified in TECH but belong to Phase 9. Documented,
  not written.
- **Collision layer names** — `combat/` will want named physics layers (player, enemy, hurtbox,
  hitbox, world, ledge-probe). Deliberately not invented in Phase 0 because guessing them now means
  renumbering them in Phase 2. Suggest defining them as the first commit of Phase 1.
- **`.gdlintrc`** — gdtoolkit defaults are close enough; a config that fights the defaults is worth
  writing only once we have real code to lint. Suggest revisiting at the end of Phase 1.
- **`export_presets.cfg`** — cannot be authored meaningfully without the Android SDK path and the
  installed build template on this machine. Phase 1 or first device deploy.

### Uncertain / deviations

Everything below is a decision I made to fill a gap, and every one is reversible. Flagging them is
the point of this section.

1. **Vigor soft cap shape [new]** — the spec says "soft cap at 30" without a curve. I proposed
   14 HP/point → 30, then 4/point → 50, then 1/point. Reaches 520 HP at the cap.
2. **Move multiplier table [new]** — the damage formula references `move_multiplier` but no table
   exists. Proposed in `GDD.md §6.2` (light 1.00/1.05/1.25, heavy 1.55, air 1.15).
3. **Enemy stat block [new]** — HP, poise, defense, and resistances for all five enemies were not in
   the spec. First-pass numbers sized so the worked damage example (43 per light swing at Might 20)
   makes a Husk a 3-hit kill. Ember drop values are **not** first-pass — see decision 1 below.
5. **Boss names for biomes 2 and 4 [new]** — the spec says "plus one per remaining biome" without
   naming them. Proposed **Mother Thistle** (Thornwood) and **The Pale King** (Bastion, implied by
   the biome name). Rename freely.
6. **All `BiomeMood` numeric values [new]** — fog densities, ambient energies, sun colours, vignette
   and grain amounts in `TECH.md §4`. The spec gave the *relationships* (Ossuary is ×4 fog,
   ambient 0.15, reverb 0.6); the absolute values are mine and are meant to be retuned on device in
   Phase 4. That they are all in one `.tres` is precisely so this costs nothing.
7. **Fall damage, terminal velocity, max slope, weight tiers, poise regen rates, attack-token
   re-offer rule [new]** — all gaps, all proposed in the GDD, all in tuning Resources.
8. **`untyped_declaration` set to error-level.** Enforces the "untyped GDScript is a bug" standard at
   compile time. `inferred_declaration` is set to *ignore*, because `var x := 5.0` **is** static
   typing and warning on it would be noise. If the error level ever fights a legitimate pattern, say
   so and I will drop it to warning rather than silently working around it.
9. **Autoloads carry no `class_name`.** A global class whose name matches an autoload singleton is a
   hard parse error in Godot 4. This is the one documented exception to "`class_name` on every
   reusable script" and it is written into `CLAUDE.md §1`.
10. **Godot is not installed on this machine** (not on `PATH`). Nothing in Phase 0 has been opened in
    the editor or parsed by the engine — the config is written from spec. **The first thing to do
    before Phase 1 is open the project once and confirm zero errors.** `scripts/lint.sh` skips its
    engine step gracefully until `GODOT` is set.
11. **Python 3.14 is installed**, which is ahead of what gdtoolkit 4 officially supports. If
    `pip install "gdtoolkit==4.*"` fails, a 3.12 virtualenv is the fix — noted in the README.
