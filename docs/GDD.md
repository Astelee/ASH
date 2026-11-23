# Ashfall — Game Design Document

**Version:** 0.1 (Phase 0) · **Platform:** Android 16, landscape phone · **Engine:** Godot 4.5 Mobile

Values marked **[derived]** were computed from the formulas in the source spec. Values marked
**[new]** are design decisions made during Phase 0 to fill gaps in the spec — every one of them is
listed in `docs/DEV_LOG.md` for approval.

---

## 1. Premise

A dead-quiet mining village at golden hour. Something under it has been burning for a long time, and
the ash never stopped falling. You walk out of Ashfall Village into a wood that is too green, then
down into an ossuary where colour itself has been taken away. The world does not get *darker* as you
descend — it gets **wrong**, and the game tells you that with light before it tells you with words.

## 2. Pillars

1. **Weighty, readable combat.** Every attack has a visible windup, a committed animation, and a
   punishable recovery. Souls-like legibility, not hack-and-slash spam. If the player cannot name
   why they got hit, the fight is broken.
2. **Mood as a mechanic.** Light and colour tell you where you are and how safe you are. Vibrant
   amber village → sickly green wood → colourless cyan crypt. Atmosphere is one `MoodDirector` call,
   not a pile of effects.
3. **One-thumb-per-side playability.** Fully playable on a phone in landscape without a controller,
   and it must feel *deliberate* rather than mushy. Controller support is a bonus, never the
   assumption.

## 3. Player fantasy & session shape

- Target session: 8–20 minutes. Wayshrine-to-Wayshrine loops must fit inside a bus ride.
- One-handed play is **not** supported; two thumbs, landscape, phone braced.
- The game pauses hard and saves on `NOTIFICATION_APPLICATION_PAUSED`. Being interrupted by a phone
  call must never cost progress.

---

## 4. Camera & space

- **1 unit = 1 metre.** Player capsule: height **1.8 m**, radius **0.35 m**.
- Gameplay is constrained to the **XY plane**. Z is used for **depth lanes**:

| Lane | Z | Contents | Collision |
|---|---|---|---|
| Foreground clutter | +1.5 … +4 | Grass, fence posts, hanging chains, near fog cards | none |
| **Action plane** | **0** | Player, enemies, platforms, pickups, hitboxes | full |
| Near backdrop | −6 | Building faces, tree trunks, structural silhouette | none |
| Mid backdrop | −14 | Rooflines, canopy mass, cliff faces | none |
| Far backdrop | −40 | Sky-adjacent silhouette, mountains, cathedral bulk | none |

Foreground clutter must never occlude the player capsule for more than ~0.4 s of travel, and never
during a combat encounter — clutter is culled or faded inside encounter volumes.

### Camera rig

| Property | Value |
|---|---|
| Projection | Perspective (**not** orthographic — we want parallax) |
| FOV | 42° (vertical — Godot's `keep_height`) |
| Offset | Z **+8.0** *(revised from +12.5 — see below)*, Y **+2.4** |
| Rotation | yaw 0°, pitch **−6°** |
| Horizontal damping | 0.12 s |
| Vertical damping | 0.28 s |
| Look-ahead | 1.8 m in facing direction |
| Dead zone | 0.6 m |
| Vertical snap | **only when grounded** (kills jump bobbing) |

**Camera distance revised: Z +12.5 → +8.0 [deviation].** At the spec's +12.5 the visible frame is
9.6 m tall — on a 20:9 phone that is **21.3 m of level width**, and a 1.8 m player occupies **19 %**
of screen height, roughly 1.4 cm tall on a 6.5" panel. A 0.65 s Husk wind-up is not readable at that
size, and readability is Pillar 1. Pulling the camera in (rather than narrowing the FOV) fixes it
**and increases parallax**, because parallax separation between depth lanes grows as the camera
approaches the action plane.

Frame dimensions at Z +8.0 **[derived]**, `height = 2 × 8 × tan(fov / 2)`:

| Context | FOV | Frame height | Width @ 20:9 | Player height | Note |
|---|---|---|---|---|---|
| Crypt corridor | 34 | 4.89 m | 10.9 m | 36.8 % | Claustrophobic, walls crowd in |
| **Default** | **42** | **6.14 m** | **13.6 m** | **29.3 %** | Target band for combat readability |
| Boss arena | 50 | 7.46 m | 16.6 m | 24.1 % | Reads the whole arena and the boss silhouette |

FOV is `MoodDirector`-drivable; camera Z is not (it is a gameplay constant, and changing distance
mid-fight changes parallax, which reads as the world moving rather than the camera).

Both FOV and Z live in `data/tuning/tuning_camera.tres` — **verify on the actual phone in Phase 1**
and expect to move Z by a metre either way.

---

## 5. Movement

Source of truth: `res://data/tuning/tuning_movement.tres`. Nothing in this table may be a literal in
a script.

| Property | Value |
|---|---|
| Walk speed | 3.2 m/s |
| Sprint speed | 6.0 m/s |
| Ground accel / decel | 45 / 60 m/s² |
| Air control | 35 % of ground accel (15.75 m/s²) **[derived]** |
| Jump apex height | 2.2 m |
| Jump initial velocity | **10.022 m/s** **[derived]** — see the integrator note below |
| Gravity | 22 m/s²; **×1.6 when falling** (35.2 m/s²) |
| Coyote time | 0.12 s |
| Jump buffer | 0.15 s |
| Ledge grab reach | 0.5 m forward, 0.3 m down |
| Landing recovery | 0.10 s |
| Hard landing recovery | 0.28 s from a fall > 6 m, with fall damage |
| Fall damage | 0 below 6 m; `(fall_m − 6) × 8` HP above it **[new]** |
| Terminal velocity | 40 m/s **[new]** |
| Max walkable slope | 46° **[new]** |

Jump feel is defined by coyote time + buffer working *together*: a buffered jump pressed up to
0.15 s before landing fires on the landing frame; a coyote jump up to 0.12 s after leaving a ledge
still fires. Both must be verifiable in the movement gym.

#### Jump velocity is integrator-corrected, not textbook

`sqrt(2 · g · h)` = **9.8387 m/s** is the launch velocity for *continuous* motion. We integrate in
discrete 60 Hz steps with gravity applied before the move, so every step travels at the velocity
from the **end** of its interval rather than the middle. Summing the discrete series gives a real
apex of **2.118 m** — a 3.7 % shortfall that looks perfectly correct on screen and would only ever
surface as "the jump feels slightly short."

Adding back half a step of gravity makes each step travel at its midpoint velocity, which is exact
for constant acceleration:

```
v0 = sqrt(2 · g · h) + g · Δt / 2
   = 9.8387 + 22.0 / 120
   = 10.0220 m/s          → measured apex 2.2012 m
```

`MovementTuning.jump_velocity()` derives this from `Engine.physics_ticks_per_second`, so changing
the physics rate re-derives it rather than silently changing the jump height.

**This is why `tests/MovementCheck.tscn` exists.** Phase 1's acceptance criteria are numeric, and
this class of error is invisible to playtesting.

---

## 6. Combat

### 6.1 Attack timing

Source of truth: `res://data/tuning/tuning_combat.tres`.

| Move | Windup | Active | Recovery | Total | Stamina |
|---|---|---|---|---|---|
| Light | 0.30 s | 0.10 s | 0.35 s | 0.75 s | 12 |
| Heavy | 0.55 s | 0.14 s | 0.65 s | 1.34 s | 25 |
| Heavy (charged) | up to 1.20 s | 0.14 s | 0.65 s | ≤ 1.99 s | 25 |
| Dodge roll | — | i-frames 0.08 → 0.32 s | — | 0.50 s | 20 |
| Parry window | — | **0.18 s** button / **0.24 s** touch | — | — | (block cost) |

- **Light combo:** 3 hits. Combo window **0.45 s** after the active frames end. Missing the window
  drops to neutral, it does not queue.
- **Charged heavy:** holding to full 1.20 s gives **×1.8 damage** and a **guaranteed poise break**.
- **Dodge:** 3.4 m travel over 0.50 s. i-frames cover 0.24 s of that **[derived]**, extended by
  Finesse.
- **Parry success:** attacker enters a **1.5 s riposte-vulnerable** state; player gains **15 stamina**.

#### Parry window is input-dependent **[deviation]**

The spec gives a flat 0.18 s. Android touch-to-photon latency is **60–100 ms**, which leaves a touch
player 80–120 ms of real reaction budget — and the Warden is *designed* to require the parry. A flat
0.18 s makes a core mechanic effectively undoable on the target platform.

So the window is a tuning value keyed to the active input device, read from `InputRouter`:

| Input device | Parry window | Rationale |
|---|---|---|
| Gamepad / keyboard | 0.18 s | Spec value. Low-latency path. |
| **Touch** | **0.24 s** | 0.18 s + a 60 ms latency allowance |

Both live in `tuning_combat.tres` as `parry_window_button` / `parry_window_touch`. **This is a guess
until it is measured**: Phase 2 must instrument real touch-to-response latency on the device and
re-derive the touch value from it. Do not treat 0.24 as validated.

### 6.1b Blocking — shield absorption, not double mitigation **[deviation]**

The spec's "absorbs `100 × mitigation%` of damage" reuses the defender's own `defense`, which would
apply armour mitigation **twice** and make blocking scale with the wrong stat. Replaced with the
genre-standard two-number shield model — absorption for damage, stability for stamina:

```
after_armor   = incoming × (1 - mitigation) × (1 - resist[type])   # the normal §6.4 chain
block_absorb  = shield.absorption[damage_type]                     # 0.00 … 0.95, from the .tres
final         = max(1.0, after_armor × (1 - block_absorb))

stability     = clamp(shield.stability_base + might × 0.006, 0.0, 0.70)
stamina_cost  = (15 + incoming_raw × 0.5) × (1 - stability)
```

- **Absorption** is a property of the shield alone — it does not scale with any stat. A 95 %
  greatshield is a gear decision, not a build decision.
- **Stability** is where **Might** pays off, exactly as the stat description promises ("block
  stability"). Capped at 0.70 so blocking is never free.
- Stamina hitting zero = **guard break** → 1.2 s stagger.

Worked case: a 100-damage hit, armour mitigation 20 %, wooden shield (absorption 0.65, stability
base 0.30), Might 20 → `after_armor` 80 → **final 28.0**; stamina cost
`(15 + 50) × (1 - 0.42)` = **37.7**.

### 6.2 Move multipliers **[new]**

The formula references `move_multiplier`, `charge_multiplier`, and `riposte_multiplier` but the spec
does not table them. Proposed:

| Move | Damage × | Poise damage | Stamina |
|---|---|---|---|
| Light 1 | 1.00 | 12 | 12 |
| Light 2 | 1.05 | 12 | 12 |
| Light 3 | 1.25 | 22 | 14 |
| Heavy | 1.55 | 38 | 25 |
| Charged heavy | 1.55 × **1.80** | **∞** (guaranteed break) | 25 |
| Air attack | 1.15 | 18 | 14 |
| Riposte | × **2.20** | — | 0 |

### 6.3 Poise

Every actor has poise. Hits apply poise damage; on break the actor is **staggered** and the next hit
is riposte-tier (**×2.2**). Player poise regenerates starting **1 s after the last hit taken**, at
**25 poise/s** **[new]**. Enemy poise regenerates at **15/s** after 2 s **[new]**.

### 6.4 Damage formula — **must be unit tested**

```
scale_bonus = Σ over stats:  weapon.scaling[stat] × attacker.stat / 40.0
raw         = weapon.base × (1 + scale_bonus)
raw        *= move_multiplier × charge_multiplier × riposte_multiplier
mitigation  = defender.defense / (defender.defense + 100.0)     # diminishing, never 100 %
final       = max(1.0, raw × (1 - mitigation) × (1 - resist[damage_type]))
```

**Scaling is a sum across all five stats, not a single stat [deviation].** The spec wrote
`weapon.scaling[stat]` as if each weapon had exactly one scaling stat, but the stat descriptions
already imply hybrids — Might for heavy weapons, Finesse for fast ones, and a quality build wants
both. A per-stat coefficient vector is strictly more general: a single-stat weapon simply has zeros
in the other four slots, and the worked example below is unchanged. This costs nothing and unlocks
the whole build space.

**Scaling grades** — the coefficient is authored as a letter in the `.tres` and shown as a letter in
the UI, per genre convention:

| Grade | E | D | C | B | A | S |
|---|---|---|---|---|---|---|
| Coefficient | 0.10 | 0.25 | 0.40 | 0.55 | 0.75 | 1.00 |

An **S**-scaling weapon at stat 40 doubles its base damage. Stat 40 is the reference point in the
denominator for exactly that reason.

**Mitigation curve** — the reason there is no armour that makes you invulnerable:

| Defense | 0 | 25 | 50 | 100 | 200 | 400 |
|---|---|---|---|---|---|---|
| Mitigation | 0 % | 20 % | 33.3 % | 50 % | 66.7 % | 80 % |

**Worked case (goes straight into the test suite):** Ashen Longsword `base 42`, `scaling.might B
(0.55)`, all other grades absent, attacker Might **20**, light-1 vs Husk (`defense 24`,
`resist.physical 0.0`):

```
raw        = 42 × (1 + 0.55 × 20 / 40)   = 42 × 1.275 = 53.55
mitigation = 24 / 124                     = 0.19355
final      = 53.55 × 0.80645 × 1.0        = 43.19
```

Same swing as a **riposte**: `53.55 × 2.2 = 117.81` → `× 0.80645` = **95.01**.

### 6.5 Damage types

**Physical · Fire · Rot · Holy.** Enemies carry per-type resistances in their `.tres`. Resistance is
a 0–1 fraction and may be **negative** (a weakness). The Ossuary Deep roster is built to punish pure
physical builds — bring Fire or Holy or bring patience.

### 6.6 Hitstop

| Event | Freeze |
|---|---|
| Light hit | 60 ms |
| Heavy hit | 110 ms |
| Riposte / kill | 180 ms |

**Implementation is non-negotiable:** freeze **only the two actors involved**, via
`AnimationPlayer.speed_scale` plus the shader hit flash. Never `Engine.time_scale`. Global time
scaling on mobile desynchronises touch input and makes the game feel drunk.

### 6.7 AI contract

Every enemy is the same state machine:

```
Idle → Alert → Approach → Attack → Recover → Reposition → Stagger → Dead
```

A shared **`AttackScheduler`** hands out **attack tokens**: at most **2 enemies may be in the Attack
state simultaneously**, per encounter volume. Everyone else circles in Reposition. This single
system is the difference between a fair fight and a mob pile-on, and it gets a unit test.

Token rules **[new]**: a token is held from windup start to recovery end; an enemy that takes a
poise break drops its token immediately; tokens are re-offered to the enemy with the best approach
angle to the player's facing, not the nearest one.

---

## 7. Progression

### 7.1 Currency

**Embers.** Dropped by enemies, spent on levels at Wayshrines. One currency — no split XP/gold.

### 7.2 Level cost curve

```
cost(level) = floor(90 × level ^ 1.535)     # Embers to go from `level` to `level + 1`
```

**Exponent 1.535, not 1.52** — this resolves the spec's internal contradiction. At 1.52 the two
anchor points could not both hold; at 1.535, **1 → 2 = 90** exactly and **30 → 31 = 16,658**, which
is the spec's "≈ 17,000". Both anchors land.

| Level → | Cost | Reach | Level → | Cost | Reach |
|---|---|---|---|---|---|
| 1 → 2 | 90 | 90 | 16 → 17 | 6,346 | 43,273 |
| 2 → 3 | 260 | 350 | 17 → 18 | 6,965 | 50,238 |
| 3 → 4 | 485 | 835 | 18 → 19 | 7,604 | 57,842 |
| 4 → 5 | 755 | 1,590 | 19 → 20 | 8,262 | 66,104 |
| 5 → 6 | 1,064 | 2,654 | 20 → 21 | 8,939 | 75,043 |
| 6 → 7 | 1,408 | 4,062 | 21 → 22 | 9,634 | 84,677 |
| 7 → 8 | 1,784 | 5,846 | 22 → 23 | 10,348 | 95,025 |
| 8 → 9 | 2,190 | 8,036 | 23 → 24 | 11,078 | 106,103 |
| 9 → 10 | 2,624 | 10,660 | 24 → 25 | 11,826 | 117,929 |
| 10 → 11 | 3,084 | 13,744 | 25 → 26 | 12,591 | 130,520 |
| 11 → 12 | 3,570 | 17,314 | 26 → 27 | 13,372 | 143,892 |
| 12 → 13 | 4,081 | 21,395 | 27 → 28 | 14,170 | 158,062 |
| 13 → 14 | 4,614 | 26,009 | 28 → 29 | 14,984 | 173,046 |
| 14 → 15 | 5,170 | 31,179 | 29 → 30 | 15,813 | 188,859 |
| 15 → 16 | 5,748 | 36,927 | **30 → 31** | **16,658** | 205,517 |

"Reach" = cumulative Embers to arrive at the *next* level from level 1. All **[derived]**; the table
is generated, not hand-typed, and `tests/test_progression.gd` regenerates and asserts it.

The formula lives in exactly one place: `systems/progression.gd`. It is unit tested.

#### Genre conventions this adopts deliberately

These are the load-bearing rules from the Souls family. They are conventions because they work, and
because players arrive already knowing them:

1. **One currency is both XP and money.** Souls, runes, blood echoes — Embers. Every purchase
   competes with levelling, which is what makes spending a decision rather than a formality.
2. **Cost depends only on total character level, never on which stat you buy.** This is the defining
   FromSoft rule. It kills dump-stat arbitrage, makes a level number mean something comparable
   between builds, and keeps the UI honest — one price, shown before you commit.
3. **You level only at a checkpoint.** Wayshrines, i.e. bonfires / sites of grace.
4. **Death drops the entire carried balance at the death site; exactly one recovery attempt.**
5. **No hard level cap** — the curve just makes further levels irrelevant. Soft caps do the work.
6. **Cheap early levels.** The first three levels cost 835 Embers combined, roughly seven Husks.
   Visible progress inside the first ten minutes.

#### Why 1.535 and not the cubic

Dark Souls 3 and Elden Ring use a cubic — `0.02x³ + 3.06x² + 105.6x − 895` from SL 13 upward
([Fextralife](https://darksouls3.wiki.fextralife.com/Level)); Elden Ring's is equivalent to a ~2.5
exponent on `(level + 81)` ([rune calculators](https://infinitycalculator.com/gaming/elden-ring-level-calculator)).
Those games run to **SL 802 / RL 713**. Ashfall's useful range ends around **L40**.

Dropping a cubic onto a 40-level range makes the last five levels cost more than the entire game
before them — a wall, which on a phone with 8–20 minute sessions reads as "the game stopped." The
gentler exponent produces the same *shape* over a much shorter climb:

| Progress through the climb | Ashfall level | Cost | ×L10 | DS3 SL | Souls | ×SL30 |
|---|---|---|---|---|---|---|
| 25 % | 10 | 3,084 | 1.00 | 30 | 5,567 | 1.00 |
| 50 % | 20 | 8,939 | 2.90 | 60 | 20,777 | 3.73 |
| 75 % | 30 | 16,658 | 5.40 | 90 | 47,975 | 8.62 |
| 100 % | 40 | 25,906 | 8.40 | 120 | 90,401 | 16.24 |

Half of the total Ember spend to reach L40 happens after L30 — the back half of the climb still
costs what it should, without a cliff.

#### 7.2b Ember economy — the curve has to be payable **[new]**

A cost curve with no drop table behind it is fiction. Solved against the Phase 5 Ashfall Village
census:

| | Count | Drop | Subtotal |
|---|---|---|---|
| Husk | 60 | 120 | 7,200 |
| Gravewretch | 25 | 60 | 1,500 |
| Crow-Mask Cultist | 15 | 175 | 2,625 |
| Warden | 6 | 400 | 2,400 |
| Bell-Bearer | 2 | 900 | 1,800 |
| **Ser Cadwyn** | 1 | 4,500 | 4,500 |
| | | **Total** | **20,025** |

One full clear, no grinding, lands the player at **L12** — a genre-appropriate level for leaving a
first area. Because enemies respawn on rest, further levels cost laps:

| Target | Extra Embers | Extra full laps of the village |
|---|---|---|
| L12 | 0 | 0.0 |
| L15 | 11,154 | 0.7 |
| L20 | 46,079 | 3.0 |
| L25 | 97,904 | 6.3 |

L15 for less than one extra lap is a fair offer. L25 costing six laps is the curve correctly saying
"go to the next area instead."

**Drop scaling per biome [new]** — a flat drop table cannot serve a curve that grows 288× across the
climb. Trash drops multiply by tier: **Biome 1 ×1.0 · Biome 2 ×2.4 · Biome 3 ×5.5 · Biome 4 ×12.0**.
One `ember_multiplier` float on the biome Resource; enemy `.tres` files keep their base value.

### 7.3 Stats

**1 point per level, +1 bonus point at every 5th level.** Total points at level *N* =
`(N - 1) + floor(N / 5)` **[derived]** — 11 points at L10, 23 at L20, 35 at L30.

| Stat | Effect |
|---|---|
| **Vigor** | Max HP `100 + vigor × 14`, soft cap at 30 |
| **Endurance** | Stamina `100 + end × 6`; regen `18 + end × 0.4` /s after 0.8 s idle |
| **Might** | Heavy-weapon scaling, block stability |
| **Finesse** | Fast-weapon scaling, roll distance, i-frame window **+0.01 s per 10 points** |
| **Ember-Bound** | Magic / consumable potency, lantern radius |

**Soft cap definition [new]** — the spec says "soft cap at 30" without a shape. Proposed: 14 HP per
point up to 30, then **4** per point to 50, then **1** per point.

| Vigor | 0 | 10 | 20 | **30** | 40 | 50 | 60 |
|---|---|---|---|---|---|---|---|
| Max HP | 100 | 240 | 380 | **520** | 560 | 600 | 610 |

| Endurance | 0 | 10 | 20 | 30 | 40 |
|---|---|---|---|---|---|
| Stamina | 100 | 160 | 220 | 280 | 340 |
| Regen /s | 18.0 | 22.0 | 26.0 | 30.0 | 34.0 |

Finesse at 40 → i-frame window 0.24 s → **0.28 s**.

**Every stat soft-caps at 30 [new].** Genre convention puts soft caps around 40–60, but those games
hand out 700+ levels. Ashfall's useful climb ends near L40, which yields **47 points** total
(`(40-1) + floor(40/5)`) — enough to take two stats to 30 and leave change. Capping at 30 keeps the
same felt shape: most of the benefit arrives in the first two-thirds, and specialising beats
spreading. Past the cap each stat follows the Vigor pattern — roughly a quarter of the pre-cap rate,
then a token trickle.

This is also what makes rule 2 in §7.2 safe: since cost depends only on total level and never on
which stat you buy, without soft caps a single-stat build would strictly dominate.

### 7.4 Skill unlocks

| Level | Unlock |
|---|---|
| 3 | Air attack |
| 7 | Charged heavy |
| 12 | Backstep-cancel |
| 18 | Parry-riposte follow-up |
| 25 | Second dodge (chained roll) |

### 7.5 Death loop

1. Die → **100 % of carried Embers** drop at the death site as a recoverable **bloodstain**.
2. Respawn at the last rested **Wayshrine**. World enemies respawn. **Boss defeat states persist.**
3. Touch the bloodstain → recover everything.
4. **Die again before recovering it → it is gone.** One bloodstain exists at a time.

### 7.6 Gear

| Slot | Carries |
|---|---|
| Weapon | Per-stat scaling vector (grades E–S) + moveset id + damage type |
| **Shield** | `absorption[damage_type]` + `stability_base` — see §6.1b **[new slot]** |
| Armour set | Defense, poise, **weight**; weight tier changes roll speed |
| Trinket ×2 | Passive modifiers |
| Lantern | Radius + fuel — a light source **and** a fear timer in the crypt |

Weight tiers **[new]**: Light < 30 % capacity (roll 0.45 s, 3.8 m) · Medium < 70 % (0.50 s, 3.4 m) ·
Heavy ≥ 70 % (0.58 s, 2.9 m, i-frames unchanged).

A **shield slot** is implied by the block/parry mechanics but was never listed in the spec's gear
table. Blocking without a shield equipped uses the weapon's own (much worse) absorption values, so
the slot is never empty in practice.

### 7.7 Healing — the Ashen Flask **[new]**

The spec never defines a healing resource. A Souls-like cannot function without one: the entire
risk/reward loop of "push one more room or walk back to the checkpoint" is built on a finite,
checkpoint-refilled heal. This fills that gap along the most conventional lines available, because
this is a mechanic players already know how to read.

| Property | Value |
|---|---|
| Charges | **3** at start, up to **8** |
| Heal amount | `flask_base × (1 + ember_bound × 0.015)` |
| `flask_base` | 90 HP at flask level 1 |
| Drink duration | **1.10 s**, fully committed |
| Heal applied at | **0.55 s** — mid-animation, not on the first frame |
| Refill | Wayshrine rest (also refills lantern fuel) |
| Movement while drinking | Walk speed only; no dodge cancel |

**The heal lands at 0.55 s, halfway through a committed 1.10 s animation.** That single number is
what makes healing a decision instead of a reflex — drinking inside an enemy's attack window gets
you hit before the HP arrives. It is the most important value in this table.

Scaling and upgrades, deliberately kept off a second currency:

- **Potency** scales with **Ember-Bound**, which is the stat's stated job ("consumable potency"). At
  Ember-Bound 20 the flask heals `90 × 1.30` = **117 HP**.
- **Charge count** comes from finding **Ash Shards** in the world — one per shard, cashed in at a
  Wayshrine. Placement is level-design pacing, not a shop.
- **`flask_base`** upgrades at Wayshrines with Embers, competing directly with levelling. That
  competition is the point.

---

## 8. Biomes

| # | Biome | Palette | Mood technique | Boss |
|---|---|---|---|---|
| 1 | **Ashfall Village** | Warm amber, deep teal shadows, high saturation | Golden dusk, drifting embers, long soft shadows, warm rim light. The "vibrant" showcase. | Ser Cadwyn the Rusted |
| 2 | **Thornwood** | Vibrant emerald → sickly yellow-green | Saturation *rises* then goes wrong. God-ray shafts through canopy, knee-height fog cards, wind intensity ramps as you go deeper. | Mother Thistle **[new]** |
| 3 | **The Ossuary Deep** | Desaturated cyan / bone, near-black shadows | **Eerie mode**: ambient energy 0.15, fog density ×4, LUT crushes reds to grey, the lantern is the only warm light, subtle chromatic aberration + grain, reverb wet 0.6, music drops to sub-bass drone only. | The Hollow Choir |
| 4 | **Bastion of the Pale King** | Storm blue-violet, magenta lightning | High contrast, rain shader, lightning flashes that momentarily blow out exposure and reveal silhouettes. | The Pale King **[new]** |

The emotional arc is *saturation*, not brightness: Biome 2 is the **most** saturated place in the
game right before it turns. Biome 3 lands harder because of what came before it.

Numeric `BiomeMood` parameter targets live in `docs/TECH.md §MoodDirector`.

---

## 9. Enemy roster

Base values at biome-1 scaling; per-biome variants scale HP/defense via the `.tres`, not new scripts.

| Enemy | HP | Poise | Def | Embers | Resists | Role |
|---|---|---|---|---|---|---|
| **Husk** | 120 | 40 | 24 | 120 | — | Shambling melee, telegraphed overhead. Tutorial enemy. |
| **Crow-Mask Cultist** | 90 | 25 | 18 | 175 | Rot +50 % | Ranged rot flasks, retreats when closed on. |
| **Warden** | 260 | 95 | 46 | 400 | Phys +40 %, Fire −25 % | Shield + spear. Must be parried or flanked. Teaches parry. |
| **Gravewretch** | 55 | 15 | 12 | 60 | Holy −50 % | Fast crawler, packs of 4–6, audible cue before an off-screen lunge. |
| **Bell-Bearer** *(elite)* | 340 | 120 | 40 | 900 | Phys +30 % | Buffs nearby enemies. Kill priority. Ringing is audible before it is visible. |

Ember values shown are **Biome 1 base**; multiply by the biome's `ember_multiplier` (§7.2b).
Ser Cadwyn drops **4,500**.

**[new]** — HP, poise, defense, and resistances are not in the source spec; these are first-pass
numbers sized against the worked damage example (a light-1 at Might 20 does ~43, so a Husk is a
3-hit kill). The **Ember values are not free parameters** — they were solved backwards from the
level curve in §7.2b so that one full clear of the village lands the player at L12. Changing a drop
value means re-checking that table.

### Tells — the readability contract

| Enemy | Tell | Counter |
|---|---|---|
| Husk | Shoulder rises, 0.65 s overhead wind-up, weapon glints | Roll through or trade |
| Crow-Mask | Arm cocks back, flask emissive ramps | Close distance; it cannot melee |
| Warden | Spear pulls to shoulder, shield audibly plants | **Parry** the thrust, or flank the shield side |
| Gravewretch | **Audio-only** rattle 0.5 s before an off-screen lunge | Roll toward the sound |
| Bell-Bearer | Bell rings on a 4 s loop, audible through walls | Kill it first — the buff is an aura, not a cast |

The Gravewretch tell is deliberately audio-first: it is the game teaching you that sound carries
information, which is what makes the Ossuary work.

### Bosses

| Boss | Biome | Structure |
|---|---|---|
| **Ser Cadwyn the Rusted** | 1 | 2 phases, arena + adds. Phase 2 at 55 % HP: rust-cloud AoE, faster combo strings, 2 Husks spawn on a timer. |
| **The Hollow Choir** | 3 | **3 bodies sharing one HP pool.** Damage to any body drains the shared pool; killing a body silences one voice and buffs the others. |
| **Mother Thistle** | 2 | **[new]** |
| **The Pale King** | 4 | **[new]** |

**Scope note.** Biomes 2–4 and their bosses are *designed* here but explicitly **out of the Phase
1–9 build plan**. See `docs/PLAN.md` — Biome 1 ships first, at shipping quality, before Biome 2
starts.

---

## 10. Wayshrines

Rest at a Wayshrine to: restore HP/stamina, refill lantern fuel and healing charges, allocate levels,
respawn all world enemies (bosses excluded), set the respawn point, and **autosave**.

Wayshrines are also the shortcut graph: Ashfall Village opens a one-way gate that becomes two-way,
so the second run through is a third the length of the first.

---

## 11. Accessibility commitments (built in Phase 7, designed now)

- Colourblind palettes that preserve the *saturation* arc, since mood is load-bearing.
- Hold-vs-toggle for sprint and block.
- Reduced camera shake, damage-numbers toggle, subtitle size.
- Touch layout fully customisable: drag, scale, opacity per button.
- Every string in a CSV from day one — no literals in UI scenes.
