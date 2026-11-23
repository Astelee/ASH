class_name Projectile
extends Area3D

## A thrown attack — the Crow-Mask Cultist's rot flask, and anything later that leaves a hand.
##
## Carries a [DamagePacket] built by its thrower at launch, so damage is decided at the moment of
## the throw rather than on impact. A cultist that dies mid-flight still lands its flask, which is
## both fairer and one less null check.
##
## Travels a ballistic arc rather than a straight line: an arc is readable from side-on, and reading
## the incoming attack is the entire point of a ranged enemy in a Souls-like.

## Emitted on any impact, before the projectile frees itself.
signal impacted(at: Vector3)

## Metres per second along the launch direction.
@export var speed: float = 11.0

## Gravity applied to the arc, m/s². Lower than world gravity so the flask hangs readably.
@export var arc_gravity: float = 14.0

## Seconds before it despawns even if it hits nothing.
@export var lifetime: float = 5.0

## Radius within which the impact damages the target, metres. Zero means contact-only.
@export var splash_radius: float = 0.0

var _velocity: Vector3 = Vector3.ZERO
var _packet: DamagePacket
var _age: float = 0.0
var _spent: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _spent:
		return

	_age += delta
	if _age >= lifetime:
		_expire()
		return

	_velocity.y -= arc_gravity * delta
	global_position += _velocity * delta
	global_position.z = 0.0


## Fire toward [param target] carrying [param packet].
##
## The launch angle is solved for the actual distance rather than fixed, so a flask thrown at 4 m
## and one at 12 m both land on the player instead of the near one sailing over their head.
func launch(from: Vector3, target: Vector3, packet: DamagePacket) -> void:
	global_position = from
	_packet = packet
	_age = 0.0
	_spent = false

	var to_target := target - from
	var range_x := absf(to_target.x)
	var rise := to_target.y

	# Ballistic solve at a fixed speed: pick the shallower of the two arcs so the flask arrives
	# quickly enough to threaten, but still visibly arcs.
	var v2 := speed * speed
	var root := v2 * v2 - arc_gravity * (arc_gravity * range_x * range_x + 2.0 * rise * v2)
	var angle := PI * 0.25
	if root >= 0.0:
		angle = atan((v2 - sqrt(root)) / (arc_gravity * maxf(range_x, 0.01)))

	var direction := signf(to_target.x)
	if is_zero_approx(direction):
		direction = 1.0
	_velocity = Vector3(cos(angle) * speed * direction, sin(angle) * speed, 0.0)


func _on_body_entered(body: Node3D) -> void:
	# Terrain. The flask breaks, and splash still reaches anyone standing in it.
	if body is StaticBody3D or body is CSGShape3D:
		_burst()


func _on_area_entered(area: Area3D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox == null or _packet == null:
		return
	if hurtbox.actor == _packet.source:
		return
	_packet.impact_point = global_position
	hurtbox.take(_packet)
	_burst()


func _burst() -> void:
	if _spent:
		return
	_spent = true
	impacted.emit(global_position)

	if splash_radius > 0.0 and _packet != null:
		for node: Node in get_tree().get_nodes_in_group(&"player"):
			var target := node as Node3D
			if target == null or target == _packet.source:
				continue
			if target.global_position.distance_to(global_position) <= splash_radius:
				var hurtbox := target.get_node_or_null("Hurtbox") as Hurtbox
				if hurtbox != null:
					hurtbox.take(_packet)
	queue_free()


func _expire() -> void:
	_spent = true
	queue_free()
