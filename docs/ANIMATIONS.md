# Ashfall — Animation Contract

**This document is the contract. Code never contains an animation name as an inline string literal.**

Every name below becomes a constant (`const ANIM_ATTACK_LIGHT_1 := "attack_light_1"`) in the owning
actor's script or a shared `AnimNames` class. Adding an animation means **editing this file first**,
then the constant, then the `AnimationPlayer`. Inventing a name in code is a violation of
`CLAUDE.md §4.3`.

## Naming rules

- `snake_case`, lowercase, no spaces.
- `<action>` · `<action>_<variant>` · `<action>_<index>` for combo steps.
- Loops carry no suffix (`idle`, `run`). One-shots carry no suffix either — looping is a property of
  the clip, not the name.
- Directional variants are `_fwd` / `_back` / `_left` / `_right`.
- Never encode timing in the name. Timing lives in `tuning_combat.tres`; the clip is retimed to it.

## Timing contract

For every attack clip, the **windup / active / recovery** boundaries are marked with
`AnimationPlayer` call-method or method-track keys, and those boundaries must match
`data/tuning/tuning_combat.tres`. If the clip and the tuning disagree, **the tuning wins** and the
clip is retimed — never the other way round, because tuning is what I rebalance without a rebuild.

---

## Player — 32 clips *(authoritative from Phase 1)*

### Locomotion (Phase 1)
`idle` · `walk` · `run` · `sprint` · `turn` ·
`jump_start` · `jump_apex` · `fall` · `land_soft` · `land_hard` ·
`ledge_grab` · `ledge_climb`

### Combat (Phase 2)
`attack_light_1` · `attack_light_2` · `attack_light_3` ·
`attack_heavy` · `attack_heavy_charge` · `attack_heavy_release` · `attack_air` ·
`dodge_roll` ·
`block_start` · `block_hold` · `block_hit` · `guard_break` ·
`parry` · `riposte` ·
`hit_react_light` · `hit_react_heavy` · `stagger` · `death`

### World (Phase 3 / 5)
`rest_wayshrine` · `item_use` · `interact`

---

## Enemies

Each enemy is roughly **14 clips**: `idle`, `walk`, `alert`, `approach`, 2–4 attacks with distinct
tells, `recover`, `reposition`, `hit_react`, `stagger`, `death`, plus its signature clip.

Rosters are filled in as each enemy is built. **Do not pre-populate names you have not implemented** —
an empty section is honest; a fabricated list is worse than nothing.

| Enemy | Phase | Clips | Status |
|---|---|---|---|
| Husk | 2 | ~14 | not yet defined |
| Crow-Mask Cultist | 6 | ~14 | not yet defined |
| Warden | 6 | ~16 | not yet defined |
| Gravewretch | 6 | ~12 | not yet defined |
| Bell-Bearer | 6 | ~14 | not yet defined |
| Ser Cadwyn the Rusted | 6 | ~24 (2 phases) | not yet defined |

**Budget warning.** Five enemies + player + one boss is **~130 clips**. This dominates the schedule
far more than code does. See `docs/PLAN.md §Scope reality`.
