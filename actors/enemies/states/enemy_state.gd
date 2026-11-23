class_name EnemyState
extends State

## Base for the shared enemy AI states. Resolves the typed actor once.

var enemy: Enemy


func setup() -> void:
	enemy = machine.actor as Enemy
	if enemy == null:
		Log.error("EnemyState", "%s: machine.actor is not an Enemy" % name)
