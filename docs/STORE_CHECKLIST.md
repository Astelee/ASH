# Ashfall — Play Store submission checklist

Work top to bottom. Everything marked **BLOCKING** will get an upload rejected or a build refunded.

---

## 1. Gates — must be green before anything else

```bash
./scripts/lint.sh && ./scripts/test.sh
```

`scripts/build.sh` runs both itself and refuses to build on a red suite. A build that ships a failing
test suite is worse than no build, because it looks like progress.

---

## 2. On-device measurement — **the outstanding work**

Nothing below has been done. Every "unverified on device" note in `DEV_LOG.md` resolves here, and no
amount of desktop testing substitutes for it.

- [ ] **60 FPS on mid tier** in the busiest legitimate moment — Cadwyn phase 2, two adds, fog field.
      `./scripts/perf.sh`
- [ ] **30 FPS floor on low tier** with shadows off.
- [ ] **20-minute thermal soak.** `./scripts/perf.sh --thermal`. A phone that holds 60 FPS for two
      minutes and 42 for twenty has not passed. Dynamic resolution should absorb the throttle as a
      gradual scale drop, never a stutter.
- [ ] **The fog-card depth read.** Flagged in Phase 0 as the likeliest place to lose the frame budget
      and still unmeasured. If it is too expensive, set `soft_particles = 0` on the affected tiers —
      but measure first, because the fallback looks materially worse.
- [ ] **Touch latency.** Instrument touch-arrival → rendered-response over 200+ real combat inputs at
      each tier, then set `parry_window_touch = 0.18 + p90(latency)`. The shipped 0.24 s is an
      estimate. If the real number pushes the window past ~0.30 s, the Warden needs redesigning.
- [ ] **9 mm touch targets** measured with a ruler on the actual panel.
- [ ] **Camera framing.** The player should read at ~29 % of screen height. Expect to move
      `tuning_camera.tres → offset_z` by a metre either way.
- [ ] **Force-close mid-run**, reopen, confirm the state is correct.

Record every number in `docs/DEV_LOG.md`. A measurement nobody wrote down was not taken.

---

## 3. Content — **BLOCKING, and the real remaining cost**

- [ ] Every row in `docs/ASSET_MANIFEST.md` at `final`. As of Phase 9 they are all `placeholder` or
      `missing`.
- [ ] **~130 animation clips** (`docs/ANIMATIONS.md`). This dominates the schedule far more than code
      does.
- [ ] **LUT textures.** `grade_and_grain` cross-fades two and `BiomeMood` carries the slot, but none
      exist and nothing mounts the post-process `ColorRect`. This also blocks the colourblind
      palettes, so it is an accessibility dependency, not only an art one.
- [ ] **Audio.** Every `SoundBank` is empty. ~25 footstep takes across 7 surfaces, combat impacts,
      the two gameplay tells, 5 sample-locked stems per biome, ambience beds, UI.
- [ ] Bake `LightmapGI` and commit the `.lmbake` outputs.

---

## 4. Build & signing — **BLOCKING**

- [ ] Godot **Android build template installed** (Project → Install Android Build Template).
- [ ] Export preset: `arm64-v8a`, `targetSdk 36`, `compileSdk 36`, `minSdk 26`, Gradle build on.
- [ ] Keystore generated **outside** the repo; `ASHFALL_KEYSTORE`, `ASHFALL_KEYSTORE_USER`,
      `ASHFALL_KEYSTORE_PASS` set in the environment.
- [ ] Keystore backed up somewhere that is not this machine. **Losing it means you can never update
      the app.**
- [ ] `git status` clean of `*.keystore`, `*.jks`, `export_credentials.cfg`. `.gitignore` covers all
      three — confirm nobody has forced one through.
- [ ] **16 KB page alignment.** `./scripts/build.sh aab` verifies it and fails the build if any LOAD
      segment is not `0x4000`. Devices with 16 KB pages reject 4 KB-aligned libraries.

---

## 5. Android behaviour

- [ ] Predictive back opens the pause menu, never closes the activity. (`PauseMenu` handles
      `NOTIFICATION_WM_GO_BACK_REQUEST`; confirm on a device running Android 13+.)
- [ ] Autosave on `NOTIFICATION_APPLICATION_PAUSED` verified by actually killing the app.
- [ ] Safe area correct on a notched panel and with the gesture bar shown.
- [ ] Landscape lock behaves on both rotations.
- [ ] Audio ducks correctly against a phone call and resumes after.

---

## 6. Store listing

- [ ] Package name, version code, version name.
- [ ] Icons at every density; feature graphic; 4+ screenshots at the target aspect.
- [ ] Content rating questionnaire — combat, blood, no purchases.
- [ ] Data safety form. Ashfall collects nothing; say so explicitly rather than leaving it blank.
- [ ] Privacy policy URL (required even when nothing is collected).
- [ ] Target audience and ads declarations.

---

## 7. Final pass

- [ ] Install the release AAB on a clean device and play from a fresh save to Cadwyn.
- [ ] Confirm no `Log.debug` output in the release build (`Log` is build-flag gated; verify).
- [ ] `docs/DEV_LOG.md` has a dated Phase 9 entry with the real measurements in it.
