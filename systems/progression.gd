class_name Progression
extends RefCounted

## The level cost curve and everything derived from it. See [code]docs/GDD.md §7.2[/code].
##
## Pure static functions. The curve exists in exactly one place in the project, and
## [code]tests/test_progression.gd[/code] regenerates the GDD's published table from it rather than
## hardcoding the numbers — so if this file and the design document ever disagree, the suite fails.

## Cost coefficient.
const COST_BASE: float = 90.0

## Cost exponent. **1.535, not 1.52** — it is the only value satisfying both of the spec's anchors:
## 1 → 2 costs exactly 90, and 30 → 31 costs 16,658, which is the spec's "≈ 17,000".
const COST_EXPONENT: float = 1.535

## Levels between bonus stat points.
const BONUS_POINT_INTERVAL: int = 5

## Starting level.
const STARTING_LEVEL: int = 1


## Embers to go from [param level] to [param level] + 1.
func cost(level: int) -> int:
	if level < STARTING_LEVEL:
		return 0
	return int(floor(COST_BASE * pow(float(level), COST_EXPONENT)))


## Total Embers spent to arrive at [param level] from level 1.
func cumulative_to_reach(level: int) -> int:
	var total := 0
	for step: int in range(STARTING_LEVEL, level):
		total += cost(step)
	return total


## True when [param embers] covers the next level from [param level].
func can_afford(level: int, embers: int) -> bool:
	return embers >= cost(level)


## Highest level reachable from [param level] with [param embers], and the change left over.
## Returns [code][level, remaining][/code].
func levels_affordable(level: int, embers: int) -> Array[int]:
	var reached := level
	var purse := embers
	while purse >= cost(reached):
		purse -= cost(reached)
		reached += 1
	return [reached, purse]


## Stat points earned by reaching [param level]: one per level, plus one at every fifth.
##
## 11 points at L10, 23 at L20, 35 at L30, 47 at L40.
func points_at_level(level: int) -> int:
	if level <= STARTING_LEVEL:
		return 0
	return (level - STARTING_LEVEL) + int(level / BONUS_POINT_INTERVAL)


## Points gained by the single step from [param level] to [param level] + 1. Two on a fifth level.
func points_for_level_up(level: int) -> int:
	return points_at_level(level + 1) - points_at_level(level)
