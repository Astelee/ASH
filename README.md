# ASHFALL

A 2.5D medieval dark-fantasy action game for Android. Souls-like combat on a phone, in landscape,
built so that light and colour carry as much information as the enemy animations do.

You leave a mining village at golden hour and walk down into somewhere that has had its colour taken
away. The world does not get darker as you descend — it gets **wrong**.

| | |
|---|---|
| **Engine** | Godot **4.5+** stable, **Mobile** renderer (Vulkan) |
| **Language** | GDScript, statically typed |
| **Target** | Android 16 (API 36), landscape, 1080×2400, mid-tier Snapdragon 7-series / Dimensity 8000-class |
| **Performance** | 60 FPS target, 30 FPS floor on low tier |
| **Status** | **Phases 1–9 built** — movement, combat, progression, shaders/mood, level tooling + Ashfall Village, the enemy roster + Ser Cadwyn, UI/settings, and audio. 184 tests. **Never run on a device**; see [`docs/STORE_CHECKLIST.md`](docs/STORE_CHECKLIST.md) §2. |

---

## Documentation

| File | What it is |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | **The project constitution.** Coding standards, architecture rules, performance budgets, the never-do list. Read this first. |
| [`docs/GDD.md`](docs/GDD.md) | Game design: movement, combat, progression math, enemy roster, biomes |
| [`docs/TECH.md`](docs/TECH.md) | Renderer config, shader list, lighting, `MoodDirector`, quality tiers, save format, Android export |
| [`docs/PLAN.md`](docs/PLAN.md) | Phases 1–9 with deliverables, acceptance criteria, and definitions of done |
| [`docs/DEV_LOG.md`](docs/DEV_LOG.md) | One dated entry per phase: built / deferred / uncertain |
| [`docs/ANIMATIONS.md`](docs/ANIMATIONS.md) | The animation-name contract. Code never inlines a clip name. |
| [`docs/ASSET_MANIFEST.md`](docs/ASSET_MANIFEST.md) | Every placeholder and the real asset it needs |
| [`docs/STORE_CHECKLIST.md`](docs/STORE_CHECKLIST.md) | Submission checklist, and the list of outstanding device measurements |

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| **Godot** | 4.5+ stable, **standard** build | Not the .NET build — this project is GDScript only |
| **JDK** | **17** | Required by the Gradle Android build. Godot rejects other majors. |
| **Android SDK** | Platform 36, Build-Tools 36, NDK per Godot's requirement | Easiest via Android Studio's SDK Manager |
| **Python** | 3.9–3.12 | For `gdtoolkit` (linting) only |
| **gdtoolkit** | 4.x | `pip install "gdtoolkit==4.*"` |

### Installed on this machine

| Tool | Version | Where |
|---|---|---|
| Godot | **4.7.1 stable** | `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\` |
| gdtoolkit | **4.5.0** | `%APPDATA%\Python\Python314\Scripts\` |
| Python | 3.14 | `C:\Python314\` |
| JDK | 17.0.19 | `C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot` |

- Godot was installed with `winget install GodotEngine.GodotEngine`. Because winget ran without
  admin rights it could not create the `godot` command alias, so **Godot is not on `PATH`** —
  `scripts/lint.sh` locates it automatically, and `GODOT=/path/to/binary` still overrides.
- gdtoolkit's executables live in the per-user Python scripts directory, which Git Bash does not put
  on `PATH` either. `scripts/lint.sh` adds it itself.
- For Android export, point *Editor Settings → Export → Android → Java SDK Path* at the JDK 17
  directory above.

> The project targets **Godot 4.5+**; 4.7.1 is the current stable and satisfies that. It imported
> the project without rewriting `project.godot`, so no `config/features` bump was needed.

---

## Open and run

1. Open Godot 4.5, **Import**, and select this folder's `project.godot`.
2. The renderer is already set to **Mobile** — do not change it. Forward+-only features are
   permanently out of scope (`CLAUDE.md §4.1`).
3. Press **F5** to run. The main scene is `levels/test/combat_gym.tscn`. Also try `movement_gym.tscn` and **`mood_showcase.tscn`** - walk right to cross from the village into the Ossuary. **F3** toggles the debug
   overlay.

Every scene in this project is required to run standalone on **F6**. If one crashes in isolation, it
is broken even if the game runs.

### Desktop controls

Everything is bound to keyboard **and** gamepad so you can iterate without deploying to the phone.

| Action | Key | Gamepad |
|---|---|---|
| Move | A / D | Left stick |
| Jump | Space | A |
| Light attack | J | RB |
| Heavy attack | K | RT |
| Dodge | Shift | B |
| Block / parry | L | LB |
| Interact | E | X |
| Use item | Q | Y |
| Menu | Esc | Start |

On the phone: dynamic virtual joystick under the left thumb, action buttons under the right.

---

## Lint

```bash
./scripts/lint.sh
```

Runs `gdformat --check`, `gdlint`, and `godot --headless --check-only` over every project script.
**It must exit 0 before any phase is called done.** Auto-fix formatting with:

```bash
./scripts/lint.sh --fix
```

Run it from **Git Bash** on Windows. Steps whose tool is missing are skipped with a warning rather
than failing, so a partial toolchain still gives you partial signal.

The engine step is a **full project import**, not a per-file `--check-only` pass — the latter
compiles without project context and reports every autoload reference as an undefined identifier.

## Test

```bash
./scripts/test.sh
```

Runs headless and exits non-zero on failure. Three suites:

| Suite | Proves |
|---|---|
| **GUT** `tests/test_*.gd` | Pure logic — damage formula, mitigation curve, block model, attack-token scheduler, stat derivations. Every worked example in the GDD is asserted. |
| `tests/MovementCheck.tscn` | The movement table — jump apex, coyote window, jump buffer, fall damage. |
| `tests/CombatCheck.tscn` | The wiring — that damage survives Hitbox → DamagePacket → Hurtbox intact, and that the token cap holds against live AI. |

Every invocation is wrapped in `timeout` with stdin closed: headless Godot will block forever waiting
on a console it does not have, and a gate that hangs is worse than one that fails.

---

## Android export

### One-time setup

1. **Editor Settings → Export → Android** — set the Android SDK path and the JDK 17 path.
2. **Project → Install Android Build Template.** This creates `android/build/`, which is
   `.gitignore`d — regenerate it after a Godot upgrade rather than committing it.
3. Create an export preset targeting `arm64-v8a`, `targetSdk 36`, `minSdk 26`, **Gradle build
   enabled**.

`export_presets.cfg` **is** committed. `export_credentials.cfg` — which holds keystore paths and
passwords — is **not**, and neither are `*.keystore` / `*.jks`.

### Keystore

Generate a release keystore **outside** the repository:

```bash
keytool -genkeypair -v \
  -keystore ~/keys/ashfall-release.keystore \
  -alias ashfall \
  -keyalg RSA -keysize 2048 -validity 10000
```

Reference it through environment variables, never as literals in a committed file:

```bash
export ASHFALL_KEYSTORE="$HOME/keys/ashfall-release.keystore"
export ASHFALL_KEYSTORE_USER="ashfall"
export ASHFALL_KEYSTORE_PASS="…"
```

**Losing this keystore means you can never update the app on Play.** Back it up somewhere that is
not this machine.

### Build

```bash
godot --headless --export-release "Android AAB" export/ashfall.aab
```

```bash
godot --headless --export-debug "Android APK" export/ashfall.apk && adb install -r export/ashfall.apk
```

`scripts/build.sh` wraps both plus `adb install -r` from Phase 9.

### Verify 16 KB page alignment — **required for Play Store submission**

Devices with 16 KB memory pages reject 4 KB-aligned native libraries. Godot 4.4+ builds aligned
libs, but a Gradle plugin or an old NDK in the chain can silently undo it, so **check every
release export**:

```bash
unzip -o export/ashfall.apk 'lib/*' -d /tmp/ashfall-libs && llvm-readelf -lW /tmp/ashfall-libs/lib/arm64-v8a/*.so | grep LOAD
```

Every `LOAD` segment's **Align** column must read `0x4000` (16384). `0x1000` (4096) means the upload
will be rejected.

```bash
zipalign -c -P 16 -v 4 export/ashfall.apk
```

### Profiling on device

```bash
adb shell dumpsys gfxinfo com.ashfall.game framestats
```

The in-game overlay (FPS, frame time, draw calls, triangles, VRAM, quality tier) toggles with a
three-finger tap. `scripts/perf.sh` arrives in Phase 9.

---

## Project layout

```
res://
  actors/{player,enemies,npc,bosses}/   character scenes + scripts
  combat/                               hitbox, hurtbox, damage packet, status effects
  systems/                              autoloads + pure, testable logic
  data/{tuning,enemies,items,biomes,stats}/   .tres Resources — all tuning lives here
  levels/{chunks,biomes,test}/
  art/{models,textures,materials,vfx,lut}/
  shaders/{surface,post,vfx}/
  ui/{hud,menus,components}/
  audio/{music,sfx,ambience,buses}/
  tests/                                GUT tests
  tools/                                editor plugins, build scripts
docs/                                   design + technical documentation
scripts/                                lint.sh (test.sh, build.sh, perf.sh to come)
```

---

## Working rules

- **Phases are gates.** Phase N+1 does not start until Phase N is reviewed. See
  [`docs/PLAN.md`](docs/PLAN.md).
- **Nothing tunable is hardcoded.** If you would ever want to change a number without a rebuild, it
  belongs in a `.tres` under `data/tuning/`.
- **Mobile renderer constraints are the design.** No volumetric fog, SSAO, SSIL, SSR, SDFGI, DOF, or
  subsurface scattering — every atmospheric effect is a deliberate fake.
- **Deviations get logged.** Any departure from the GDD or TECH spec goes in `docs/DEV_LOG.md` with
  its reason, in the same commit.
