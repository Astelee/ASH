class_name EncounterDirector
extends Node

## Owns one [AttackScheduler] for the enemies in a level.
##
## A node in the scene rather than a tenth autoload — [code]CLAUDE.md §2[/code] sets the bar for
## global state at "two unrelated systems need it and nothing in the tree can own it", and a level
## owns its own encounter perfectly well. It also means a boss arena can cap its adds at one token
## while the level around it uses two.
##
## Enemies find it by group and degrade gracefully: with no director present they simply attack
## whenever they like, which keeps a single enemy runnable on F6.

## Concurrent attackers allowed across this encounter.
@export var max_attackers: int = 2

## The scheduler enemies claim tokens from.
var scheduler: AttackScheduler


func _ready() -> void:
	add_to_group(&"encounter")
	scheduler = AttackScheduler.new(max_attackers)


## Enemies currently mid-swing.
func attacking_count() -> int:
	return scheduler.active_count() if scheduler != null else 0


## Enemies queued for a turn.
func waiting_count() -> int:
	return scheduler.waiting_count() if scheduler != null else 0
