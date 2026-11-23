class_name MoodTrigger
extends Area3D

## Walk into it, the world changes. The only sanctioned way a level drives atmosphere.
##
## Holds no effect logic of its own -- it names a [BiomeMood] and a duration and hands both to
## [code]MoodDirector[/code]. That is deliberate: the moment a trigger starts tweaking fog directly,
## the "all mood is one call" guarantee is gone and the transitions stop agreeing with each other.

## Mood applied on entry.
@export var mood: BiomeMood

## Blend duration, seconds. Long enough that the player feels the place change rather than seeing it
## switch.
@export var duration: float = 3.5

## Apply again on every entry. Off for one-shot story beats.
@export var repeatable: bool = true

var _fired: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is not Player:
		return
	if _fired and not repeatable:
		return
	if mood == null:
		Log.warn("MoodTrigger", "%s has no mood assigned" % name)
		return
	_fired = true
	MoodDirector.transition_to(mood, duration)
