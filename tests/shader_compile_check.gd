extends Node3D

## Instantiates every declared shader onto real geometry and draws it, so the GPU actually compiles
## them. Run with a real rendering driver -- `--headless` uses a dummy rasteriser that skips
## compilation entirely, which means the unit suite can only prove these files parse as resources.
##
## Any compile failure lands on stderr as a SHADER ERROR; scripts/test.sh greps for it.

const SHADERS: Array[String] = [
	"surface/character_pbr",
	"surface/foliage_wind",
	"surface/terrain_triplanar",
	"surface/emissive_flicker",
	"vfx/fog_card",
	"vfx/god_ray_cone",
	"vfx/water_flow",
	"vfx/dissolve_teleport",
]

const POST_SHADERS: Array[String] = [
	"post/grade_and_grain",
	"post/grade_screen",
]

var _frames: int = 0


func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 6.0)
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.4, 0.0)
	add_child(light)

	var index := 0
	for name: String in SHADERS:
		var shader := load("res://shaders/%s.gdshader" % name) as Shader
		if shader == null:
			printerr("FAILED TO LOAD %s" % name)
			continue
		var material := ShaderMaterial.new()
		material.shader = shader

		var mesh := MeshInstance3D.new()
		mesh.mesh = SphereMesh.new()
		mesh.material_override = material
		mesh.position = Vector3(float(index % 4) * 1.6 - 2.4, float(index / 4) * -1.6 + 0.8, 0.0)
		add_child(mesh)
		index += 1

	var canvas := CanvasLayer.new()
	add_child(canvas)
	for post_name: String in POST_SHADERS:
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var post := ShaderMaterial.new()
		post.shader = load("res://shaders/%s.gdshader" % post_name) as Shader
		rect.material = post
		canvas.add_child(rect)

	print("--- shader compile check: %d spatial + %d canvas ---" % [index, POST_SHADERS.size()])


func _process(_delta: float) -> void:
	# Several frames so every material reaches a draw call and compiles.
	_frames += 1
	if _frames >= 20:
		print("--- shader compile check complete ---")
		get_tree().quit(0)
