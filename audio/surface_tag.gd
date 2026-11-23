class_name SurfaceTag
extends Node

## Marks a piece of geometry as a material — gravel, stone, wood, water, bone.
##
## A `Node` child rather than a property on the body, so a level designer can tag a chunk without
## the chunk needing a script, and so one body can carry different tags on different children later
## if it ever needs to.

## Surfaces the audio banks are named after. Adding one means adding a `step_<name>` bank; nothing
## else changes.
const KNOWN: Array[StringName] = [
	&"stone", &"gravel", &"wood", &"grass", &"water", &"bone", &"metal"
]

## Material of this surface. Appended to `step_` to find the bank.
@export var surface: StringName = &"stone"


func _ready() -> void:
	if not KNOWN.has(surface):
		Log.warn("SurfaceTag", "%s: unknown surface '%s'" % [get_path(), surface])


## Find the tag on [param node], or on its parents.
##
## Walking up matters because a tag is usually placed on a chunk root while the raycast hits a child
## collider several levels down. Returns null when nothing in the chain is tagged.
static func find_on(node: Object) -> SurfaceTag:
	var current := node as Node
	while current != null:
		for child: Node in current.get_children():
			var tag := child as SurfaceTag
			if tag != null:
				return tag
		current = current.get_parent()
	return null
