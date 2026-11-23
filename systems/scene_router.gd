extends Node

## Async scene loading, transition screens, and the level-to-level handoff contract.
##
## Wraps [ResourceLoader] threaded loading so a level swap never blocks the frame, and carries a
## small typed payload (spawn marker id, whether this is a respawn, which Wayshrine) into the
## incoming scene.
##
## Populated in Phase 5. Phase 1 loads the movement gym directly.
