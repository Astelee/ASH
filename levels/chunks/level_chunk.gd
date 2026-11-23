@tool
class_name LevelChunk
extends Node3D

## A hand-authored piece of level with named connectors at each end.
##
## Chunks snap to each other in the editor: set [member snap_to] on the inspector and the chunk
## moves so its entry connector meets that chunk's exit. Hand-placed, never procedural -- the point
## is that a designer drags pieces together and the geometry lines up, not that a generator invents
## a level.
##
## Runs as @tool so the snap happens while authoring rather than at runtime.

## Local position of the connector on the left-hand side, metres.
@export var entry_offset: Vector3 = Vector3(0.0, 0.0, 0.0):
	set(value):
		entry_offset = value
		_resnap()

## Local position of the connector on the right-hand side.
@export var exit_offset: Vector3 = Vector3(24.0, 0.0, 0.0):
	set(value):
		exit_offset = value
		_resnap()

## Chunk this one attaches to. Setting it moves this chunk so the connectors meet.
@export var snap_to: LevelChunk:
	set(value):
		snap_to = value
		_resnap()

## Identifier used by spawn markers and save flags.
@export var chunk_id: StringName = &"chunk"


## World position of this chunk's entry connector.
func entry_point() -> Vector3:
	return global_transform * entry_offset


## World position of this chunk's exit connector.
func exit_point() -> Vector3:
	return global_transform * exit_offset


## Length of the chunk along X, metres. Used by the parallax lanes to size their spans.
func span() -> float:
	return absf(exit_offset.x - entry_offset.x)


func _resnap() -> void:
	if snap_to == null or snap_to == self or not is_inside_tree():
		return
	# Move so our entry lands on their exit. Position only -- rotating chunks would break the
	# 2.5D action plane, and a chunk that needs rotating is a different chunk.
	global_position = snap_to.exit_point() - (global_transform.basis * entry_offset)
