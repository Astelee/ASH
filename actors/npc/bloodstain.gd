class_name Bloodstain
extends Area3D

## The Embers dropped where the player last died. Touch to reclaim.
##
## Placed by the level from [code]GameState[/code] rather than persisted as a scene: exactly one
## exists at a time, and dying again before reaching it destroys it for good.


func _ready() -> void:
	add_to_group(&"bloodstain")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is not Player:
		return
	var reclaimed := GameState.recover_bloodstain()
	Log.info("Bloodstain", "recovered %d Embers" % reclaimed)
	queue_free()
