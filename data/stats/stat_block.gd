class_name StatBlock
extends Resource

## The five stats and everything derived from them. See [code]docs/GDD.md §7.3[/code].
##
## Pure data plus derived getters — no node access, so the whole progression system is testable
## headless.

## The five allocatable stats. Weapon scaling is indexed by this.
enum Stat { VIGOR, ENDURANCE, MIGHT, FINESSE, EMBER_BOUND }

## Denominator in the weapon scaling formula. A stat of 40 with S scaling doubles a weapon's base.
const SCALING_REFERENCE: float = 40.0

## Every stat soft-caps here. Genre convention is 40–60, but those games hand out hundreds of
## levels; Ashfall's useful climb ends near L40 for ~47 points total.
const SOFT_CAP: int = 30

## Second breakpoint, past which returns are a token trickle.
const HARD_CAP: int = 50

@export_group("Stats")

## Max HP.
@export var vigor: int = 10

## Stamina pool and regeneration.
@export var endurance: int = 10

## Heavy-weapon scaling and block stability.
@export var might: int = 10

## Fast-weapon scaling, roll distance, i-frame window.
@export var finesse: int = 10

## Magic and consumable potency, lantern radius.
@export var ember_bound: int = 10

@export_group("Curves")

## HP at Vigor 0.
@export var health_base: float = 100.0

## HP per Vigor point below [constant SOFT_CAP].
@export var health_per_vigor: float = 14.0

## Stamina at Endurance 0.
@export var stamina_base: float = 100.0

## Stamina per Endurance point.
@export var stamina_per_endurance: float = 6.0

## Stamina regen per second at Endurance 0.
@export var stamina_regen_base: float = 18.0

## Extra regen per Endurance point.
@export var stamina_regen_per_endurance: float = 0.4

## Idle time before stamina begins recovering, seconds.
@export var stamina_regen_delay: float = 0.8

## Extra i-frame seconds per 10 points of Finesse.
@export var iframe_per_ten_finesse: float = 0.01


## Value of [param stat].
func get_stat(stat: Stat) -> int:
	match stat:
		Stat.VIGOR:
			return vigor
		Stat.ENDURANCE:
			return endurance
		Stat.MIGHT:
			return might
		Stat.FINESSE:
			return finesse
		Stat.EMBER_BOUND:
			return ember_bound
	return 0


## Max HP, with the Vigor soft cap applied.
##
## 14/point to 30, then a quarter of that to 50, then a trickle — 520 HP at the cap, 610 at 60.
## Without the taper, a single-stat build would strictly dominate, because level cost never depends
## on which stat you buy.
func max_health() -> float:
	var below := float(mini(vigor, SOFT_CAP))
	var mid := float(clampi(vigor - SOFT_CAP, 0, HARD_CAP - SOFT_CAP))
	var above := float(maxi(vigor - HARD_CAP, 0))
	return (
		health_base
		+ below * health_per_vigor
		+ mid * health_per_vigor * 0.2857
		+ above * health_per_vigor * 0.0714
	)


## Max stamina.
func max_stamina() -> float:
	return stamina_base + float(endurance) * stamina_per_endurance


## Stamina recovered per second, once the idle delay has elapsed.
func stamina_regen() -> float:
	return stamina_regen_base + float(endurance) * stamina_regen_per_endurance


## Extra invulnerability the dodge roll gains from Finesse, seconds.
func iframe_bonus() -> float:
	return float(finesse) * 0.1 * iframe_per_ten_finesse


## Deep copy, so a run's live stats never alias the authored template.
func duplicate_block() -> StatBlock:
	return duplicate(true) as StatBlock
