# Ashfall — Technical Specification

**Godot 4.5+ stable · Mobile renderer (Vulkan) · GDScript, statically typed · Android 16 (API 36)**

Values marked **[new]** are Phase 0 decisions filling gaps in the source spec; they are listed in
`docs/DEV_LOG.md` for approval.

---

## 1. Rendering strategy

**The Mobile renderer's limits are the design, not an obstacle to work around.** It gives us:

> **no volumetric fog · no SSAO/SSIL · no SSR · no SDFGI · no DOF · no subsurface scattering**

Every atmospheric effect below is a deliberate fake, built as a reusable scene or shader — never a
one-off. Switching to Forward+ to "just enable" one of these is out of scope permanently.

### Baked project settings

| Setting | Value |
|---|---|
| `rendering/renderer/rendering_method` | `"mobile"` |
| `rendering/renderer/rendering_method.mobile` | `"mobile"` |
| `display/window/size/viewport_width` × `height` | 1920 × 1080 |
| `display/window/stretch/mode` / `aspect` | `viewport` / `expand` |
| `display/window/handheld/orientation` | `4` (sensor_landscape) |
| `display/window/vsync/vsync_mode` | `1` (enabled) |
| `application/run/max_fps` | 60 default, **driven at runtime by `QualityManager`** |
| `rendering/textures/vram_compression/import_etc2_astc` | `true` |
| `rendering/anti_aliasing/quality/msaa_3d` | `2` (2×), exposed in settings, off on low |
| `rendering/scaling_3d/mode` | `0` (bilinear); `scaling_3d/scale` driven at runtime |
| `rendering/lights_and_shadows/directional_shadow/size` | 2048 |
| `…/directional_shadow/soft_shadow_filter_quality` | 1 |
| `physics/3d/default_gravity` | 22.0 |
| `physics/common/physics_ticks_per_second` | 60 |

`display/window/stretch/mode = viewport` means the 3D scene renders at 1920×1080 logical and scales
to the panel — combined with `scaling_3d/scale` this is the whole dynamic-resolution story, and the
UI stays crisp because `CanvasLayer` content is unaffected.

---

## 2. Shader list

Ten shaders. Each is its own `.gdshader` with documented uniforms, and each is authored as
`render_mode` minimal — no unused features left switched on, because the Mobile renderer compiles
what you declare.

**Art direction: grounded realism, not stylization.** Superseded the original toon spec on
2026-08-15 — see `DEV_LOG.md`. Realism on a tile-based mobile GPU comes from material response and
tonemapping, never from screen-space effects; the Forward+ ban in `CLAUDE.md §4.1` is unchanged and
none of these shaders needs it.

### `surface/character_pbr.gdshader`
Full energy-conserving PBR. The workhorse — every character, the player, every boss. Replaced
`character_toon_pbr` and its 3-band quantized diffuse.

| Uniform | Type | Purpose |
|---|---|---|
| `albedo_color` | **instance** `color` | Per-actor silhouette colour, set in the `.tscn` |
| `orm_texture` / `use_orm` | `sampler2D` / `bool` | Packed occlusion-roughness-metallic, one fetch instead of three |
| `detail_normal` / `detail_tiling` | `sampler2D` / `float` | Tight-tiled surface breakup; the cheapest realism win available |
| `diffuse_wrap` / `wrap_tint` | `float` / `color` | Wrapped diffuse standing in for the subsurface term Mobile does not have |
| `rim_color` | global `color` | **Written globally by `MoodDirector`** so characters always read against the current biome fog |
| `rim_power` | `float` | Fresnel falloff |
| `hit_flash` | **instance** `float` 0–1 | Lerps albedo → white. Driven by the hitstop system |
| `dissolve_amount` | **instance** `float` 0–1 | Noise-driven death dissolve |
| `dissolve_edge_color` | `color` | Emissive burn edge |
| `poise_break_glow` | **instance** `float` | Emissive pulse while staggered |

`rim_color` being global is what stops characters from disappearing into the Ossuary's near-black
shadows without lighting them individually.

The four **instance** uniforms are why the whole roster shares one `ShaderMaterial` and still
batches: a plain uniform would flash every enemy on screen when one got hit, and one material per
actor would multiply the draw calls instead. AO is applied to ambient only (`AO_LIGHT_AFFECT = 0`) —
folding it into direct light darkens the lit side of a face and reads as grime.

### `surface/foliage_wind.gdshader`
World-position-seeded noise vertex sway. Per-instance phase offset from `INSTANCE_CUSTOM` (so a
MultiMesh field does not pulse in unison). Wrapped diffuse, plus **view-dependent** transmission —
`pow(dot(V, -L), n)` — so a leaf glows only when you look into the light through it. The earlier
inverted-`NdotL` version glowed from every angle, which read as self-illuminated plastic.
**`alpha_scissor` only — never alpha blend.** Wind strength is a global shader uniform driven by
`MoodDirector`.

### `surface/terrain_triplanar.gdshader`
Triplanar blend for cliffs and ground so level geometry never needs UV unwrapping. Vertex-colour-
driven blend between 2 material sets, **plus slope auto-blend** so a re-cut chunk shows rock on
cliffs without an art pass. **Macro variation** — a very low-frequency noise multiplied into albedo
and roughness — breaks the visible tiling that is the single biggest tell on ground, at one extra
fetch. Detail normal layered on top, baked AO from the vertex green channel, and a wetness/mud
parameter for Biome 4 that also flattens the normals.

### `vfx/fog_card.gdshader` — **our volumetric fog replacement**
Camera-facing quad with scrolling noise. Critically: **soft-particle depth fade** via `DEPTH_TEXTURE`
so cards do not slice visibly through geometry, plus distance fade and a height gradient. Instanced
via MultiMesh; card count is a quality-tier knob (25 % / 60 % / 100 %).

### `vfx/god_ray_cone.gdshader`
Additive cone mesh with a scrolling noise mask, faded by view angle **and** by depth so it does not
visibly intersect walls. Canopy shafts (Biome 2) and crypt window light (Biome 3).

### `vfx/water_flow.gdshader`
Flowmap + depth-fade shoreline + fake screen-space refraction via `SCREEN_TEXTURE`.
**High tier only** — `SCREEN_TEXTURE` forces a screen copy. Branch it out on mid/low with a shader
variant, not a runtime `if`.

### `vfx/dissolve_teleport.gdshader` and `vfx/ember_particle.gdshader`
`GPUParticles3D` with a mobile-safe process material (no trails, no attractors, no collision).

### `post/grade_and_grain.gdshader` and `post/grade_screen.gdshader` — **one pass, two materials**
One fullscreen `ColorRect` on a `CanvasLayer` below the HUD (`ui/hud/ColorGrade.tscn`), mounting one
of two materials chosen by `QualityManager.allows_screen_texture()`.

**Exposure, ACES tonemapping, contrast, saturation and the LUT are not in either shader.**
`Environment` applies all five during the tonemap resolve, which costs no extra pass and no extra
memory, and `MoodDirector` drives them from the `BiomeMood`. Running the curve again in the quad
would tonemap the image twice and crush everything above mid-grey.

| | `grade_and_grain` (LOW/MID) | `grade_screen` (HIGH) |
|---|---|---|
| Samples the screen | no | yes |
| Texture cost | **0 MB** | **+11.8 MB** (back buffer, measured on Ashfall Village) |
| Vignette, grain, pulse | yes, as a `blend_mul` multiplier | yes |
| Chromatic aberration | no — it needs neighbouring pixels | yes |

Multiplicative grain is not a compromise: film grain is a density variation, so it scales with what
is underneath it and leaves true black alone. The earlier additive version needed an explicit
luminance term to fake exactly that.

**Do not stack multiple fullscreen quads.** Each one is a full-resolution fill-rate hit; two of them
is how a 60 FPS scene becomes a 40 FPS scene on a Mali GPU.

### `surface/emissive_flicker.gdshader`
Torches and braziers. Flicker is **per-instance noise evaluated in the shader**, never a per-frame
CPU animation on hundreds of nodes.

---

## 3. Lighting

- **One `DirectionalLight3D`** (sun/moon): 2 shadow splits, shadow distance 45 m, biome-driven
  colour / energy / angle.
- **`WorldEnvironment` per biome:** sky background (panorama or shader sky), **ambient light source =
  colour** (cheap — not a sky contribution), fog enabled (depth + height fog, which *is* supported on
  Mobile), glow at low quality with ≤ 3 levels.
- **Baked `LightmapGI`** for all static geometry, baked at import time. `.lmbake` outputs are
  committed (see `.gitignore`). Dynamic actors sample the lightmap probes.
- **Player lantern:** a shadowless `OmniLight3D` with slight flicker, parented to the hand bone. In
  Biome 3 its radius is the primary readability tool — it is a gameplay stat (`Ember-Bound`), not
  set dressing.

---

## 4. `MoodDirector`

One autoload holding one active **`BiomeMood`** Resource. `Area3D` triggers in levels call
`MoodDirector.transition_to(mood, duration)` and **every** parameter lerps together over that
duration.

**All mood is one call.** That is what makes it read as intentional rather than as shader soup.

### `BiomeMood` fields

`fog_color` · `fog_density` · `fog_height_min/max` · `ambient_color` · `ambient_energy` ·
`sun_color` · `sun_energy` · `sun_euler` · `lut_texture` · `lut_blend` · `vignette_strength` ·
`grain_amount` · `chromatic_aberration` · `wind_strength` · `camera_fov` · `reverb_wet` ·
`music_stem_mask` · `particle_preset` · `rim_color`

### Biome targets **[new]** — first-pass values, tune in the editor

| | 1 · Village | 2 · Thornwood | 3 · Ossuary Deep | 4 · Bastion |
|---|---|---|---|---|
| Fog colour | `#C78A4B` | `#3D6B38` | `#33474D` | `#473D6B` |
| Fog density | 0.012 | 0.020 | **0.048** (×4) | 0.030 |
| Ambient energy | 0.55 | 0.42 | **0.15** | 0.30 |
| Sun colour | `#FFC785` | `#D1F28C` | `#8CADBA` | `#9E99E6` |
| Sun energy | 1.60 | 1.20 | 0.15 | 0.70 |
| Sun elevation | −32° | −58° | −80° (fill only) | −45° |
| Vignette | 0.18 | 0.26 | **0.45** | 0.30 |
| Grain | 0.02 | 0.035 | **0.08** | 0.05 |
| Chromatic ab. | 0.00 | 0.15 | **0.35** | 0.20 |
| Wind | 0.35 | 0.75 → 1.00 | 0.08 | 1.00 |
| Camera FOV | 42 | 42 | **34** | 46 |
| Reverb wet | 0.12 | 0.30 | **0.60** | 0.40 |
| Music stems | full | full | **drone only** | full |
| Particles | ember drift | pollen / leaves | dust motes | rain |

Biome 3's row is the "eerie mode" from the GDD, expressed entirely as one Resource. Retuning the
whole feel of the crypt means editing one `.tres` and nothing else — that is the acceptance test for
Phase 4.

---

## 5. Quality tiers — `QualityManager`

| | **Low** | **Mid** | **High** |
|---|---|---|---|
| Render scale | 0.65 | 0.80 | 1.00 |
| MSAA | off | 2× | 4× |
| Shadows | off (baked only) | 1024, 1 split | 2048, 2 splits |
| Fog cards | 25 % count | 60 % | 100 % |
| Glow | off | on, 3 levels | on, 5 levels |
| Screen-texture FX | off | off | on |
| Target FPS | 30 | 60 | 60 |

- **Auto-detect on first launch** by benchmarking 3 seconds of a stress scene. Always
  user-overridable in settings.
- **Dynamic resolution:** if the 30-frame rolling average frame time exceeds the tier budget for
  **2 s**, drop `scaling_3d/scale` by **0.05** (floor **0.60**); recover slowly (0.02 steps,
  4 s of headroom required) **[new]**.
- **Never change resolution during a boss attack telegraph.** Bosses raise a hold flag on
  `QualityManager` for the duration of a wind-up; a resolution pop mid-tell reads as a dropped frame
  and gets the player killed.

---

## 6. Input — `InputRouter`

### Touch layout

- **Left thumb — dynamic virtual joystick.** The origin spawns wherever the thumb lands within the
  **left 40 %** of the screen. Dead zone **12 %**; full deflection at **45 % of a 140 px radius**.
  Dynamic origin is mandatory — a fixed stick on a phone means the thumb drifts off it inside a
  minute.
- **Right thumb** — attack (large), heavy (hold to charge, with a radial fill indicator), dodge,
  block/parry, interact (**contextual — only rendered when something is interactable**), item.

### Sizing

Touch targets are **≥ 9 mm physical**, spaced **≥ 2 mm** apart, computed from
`DisplayServer.screen_get_dpi()`:

```
px_per_mm  = dpi / 25.4
min_target = 9.0 * px_per_mm      # 400 dpi → 142 px
min_gap    = 2.0 * px_per_mm      # 400 dpi →  32 px
```

### Safe area

Read `DisplayServer.get_display_safe_area()` and inset the HUD. **Android 15+ enforces edge-to-edge**
— assume the display extends under the camera notch and the gesture bar, and that anything you pin
to a raw screen edge will be either invisible or unreachable.

### Other

- Full layout customization: drag, scale, and opacity per button, persisted in settings.
- **Haptics via `Input.vibrate_handheld()` on parry, poise break, and level-up only.** Over-buzzing
  is worse than no haptics.
- Every action is also bound to **keyboard + gamepad** — desktop testing, and controllers on Android.

### Input latency — a gameplay dependency, not a polish item

`InputRouter` exposes the active input device, and combat reads its parry window from it:
**0.18 s on gamepad/keyboard, 0.24 s on touch** (`GDD.md §6.1`). Android touch-to-photon latency
runs 60–100 ms, which would otherwise leave a touch player ~80 ms of real reaction budget on a
mechanic the Warden is designed to require.

**The 0.24 s figure is unvalidated.** Phase 2 must instrument it on the actual device before the
value is trusted:

1. Log the delta from `InputEventScreenTouch` arrival to the frame that renders the response.
2. Sample over ≥ 200 inputs during real combat, at each quality tier — render scale and frame
   pacing both move this number.
3. Set `parry_window_touch = 0.18 + p90(latency)` and record the measurement in `DEV_LOG.md`.

If measured latency pushes the window past ~0.30 s, the parry stops reading as a precision mechanic
and the Warden's design needs revisiting instead. That is a design outcome, not a bug — surface it
rather than quietly widening the window.

**Desktop bindings** (already in `project.godot`):

| Action | Key | Gamepad |
|---|---|---|
| `move_left` / `move_right` | A / D | Left stick X |
| `jump` | Space | A (0) |
| `attack_light` | J | RB (10) |
| `attack_heavy` | K | RT (axis 5) |
| `dodge` | Shift | B (1) |
| `block` | L | LB (9) |
| `interact` | E | X (2) |
| `item_use` | Q | Y (3) |
| `menu` | Esc | Start (6) |

---

## 7. Save system

**Path:** `user://saves/slot_%d.save` · **Body:** JSON · **Compression:** gzip ·
**Header:** `{"version": N, "checksum": ...}`

```json
{
  "version": 1,
  "checksum": "sha256:… covers the payload string byte-for-byte",
  "written_at": "2026-08-13T00:00:00Z",
  "build": "0.0.1",
  "payload": "<the block below, stored as an embedded JSON *string*>",
  "_shape_of_that_string": {
    "player": { "level": 7, "stats": {…}, "hp": 240.0, "embers": 1204 },
    "flask":  { "charges": 4, "max_charges": 5, "base": 90, "ash_shards_found": ["village_well"] },
    "gear":   { "weapon": "ashen_longsword", "shield": "wooden_kite", "armour": "…", "lantern": 1 },
    "world":  { "wayshrine": "village_gate", "flags": […], "bosses_defeated": […] },
    "bloodstain": { "level_id": "village_02", "position": [12.5, 3.0, 0.0], "embers": 480 }
  }
}
```

**Rules — all four are hard requirements:**

1. **Write to a temp file, then `rename()`.** Never write over the live save in place. Android can
   kill the process mid-write and a half-written save is an unrecoverable run.
2. **Explicit migration chain** — `migrate_v1_to_v2()`, `migrate_v2_to_v3()`, applied in sequence.
   Each is a pure function on a Dictionary and each gets a unit test.
3. **Loading a newer version than the build supports fails gracefully** with a user-facing message.
   Never a crash, never a silent wipe.
4. **Autosave on:** Wayshrine rest, level-up, boss defeat, and **`NOTIFICATION_APPLICATION_PAUSED`**.
   The last one is mandatory, not optional — Android kills backgrounded processes without warning.

Checksum mismatch → load the backup slot (`slot_%d.save.bak`, rotated on each successful write)
**[new]**, then warn.

---

## 8. Android build

| Setting | Value |
|---|---|
| `targetSdkVersion` | 36 |
| `compileSdk` | 36 |
| `minSdkVersion` | 26 |
| Build type | **Gradle** (custom Android build template installed) |
| Architectures | `arm64-v8a` (ship), `x86_64` (emulator testing only) |
| Textures | ETC2 / ASTC; per-tier texture quality if package size becomes a problem |
| Artifacts | **AAB** for Play, **APK** for sideload |

### 16 KB memory page alignment — **required for Play Store submission**

Devices with 16 KB pages reject 4 KB-aligned native libraries. Godot 4.4+ builds aligned libs, but
**verify every export** — a Gradle plugin or an old NDK in the chain can silently undo it:

```bash
unzip -o export/ashfall.apk 'lib/*' -d /tmp/ashfall-libs
llvm-readelf -lW /tmp/ashfall-libs/lib/arm64-v8a/*.so | grep LOAD
# Every LOAD segment's Align column must read 0x4000 (16384). 0x1000 (4096) = rejected upload.
zipalign -c -P 16 -v 4 export/ashfall.apk   # must print "Verification succesful"
```

This command is duplicated in `README.md` where it will actually get run.

### Predictive back gesture

Android 13+ predictive back must **open the pause menu, not kill the activity**. Set
`application/config/quit_on_go_back = false` and handle `NOTIFICATION_WM_GO_BACK_REQUEST` in the
root scene. Enable `android:enableOnBackInvokedCallback="true"` in the build template manifest.

### Signing

Keystore generation is documented in `README.md`. **The keystore and its passwords are never
committed** — they come from environment variables, and `.gitignore` covers `*.keystore`, `*.jks`,
and `export_credentials.cfg`.

### Scripts

| Script | Does |
|---|---|
| `scripts/lint.sh` | gdformat + gdlint + `godot --headless --check-only` (**exists**) |
| `scripts/test.sh` | GUT headless (Phase 2) |
| `scripts/build.sh` | AAB + APK export, `adb install -r` (Phase 9) |
| `scripts/perf.sh` | `adb shell dumpsys gfxinfo <pkg> framestats`, simpleperf notes (Phase 9) |

### On-device perf overlay

`DebugOverlay` shows FPS, frame time, draw calls, primitives, video memory, active quality tier, and
the current dynamic-resolution scale. Toggled by a three-finger tap on Android, a key on desktop.
Compiled out of release builds.

---

## 9. Testing

**GUT** for unit tests, headless via `scripts/test.sh`. Must pass before any phase is called done.

Mandatory coverage:

- Damage formula, including the multi-stat scaling sum and the worked example in `GDD.md §6.4`
- Mitigation curve, at defense 0 / 25 / 50 / 100 / 200 / 400
- Block model: absorption applied *after* armour mitigation (never twice), and stability clamped
  at 0.70
- XP / level cost curve at exponent 1.535 — assert both anchors (1→2 = 90, 30→31 = 16,658) and
  regenerate the whole `GDD.md §7.2` table rather than hardcoding it
- Ember economy: the §7.2b village census pays out 20,025 and lands the player at L12
- Stat derivations (HP incl. soft cap, stamina, regen, i-frame extension, flask potency)
- Save serialization round-trip
- Save migration chain (every `migrate_vN_to_vN+1` in isolation, plus v1 → latest end-to-end)
- Attack-token scheduler (never more than 2 tokens; tokens released on poise break)

Logic lives in plain `RefCounted` classes precisely so all of this runs without a scene tree.
