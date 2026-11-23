import pathlib

husk = pathlib.Path("actors/enemies/Husk.tscn").read_text(encoding="utf-8")

boss = husk
boss = boss.replace('[gd_scene load_steps=24 format=3]', '[gd_scene load_steps=27 format=3]')
boss = boss.replace(
    '[ext_resource type="Script" path="res://actors/enemies/enemy.gd" id="1_enemy"]',
    '[ext_resource type="Script" path="res://actors/bosses/boss.gd" id="1_enemy"]',
)
boss = boss.replace(
    'path="res://data/enemies/enemy_husk.tres"', 'path="res://data/enemies/boss_cadwyn.tres"'
)
boss = boss.replace(
    '[ext_resource type="Script" path="res://actors/enemies/states/enemy_lunge_state.gd" id="18_lunge"]',
    '[ext_resource type="Script" path="res://actors/enemies/states/enemy_lunge_state.gd" id="18_lunge"]\n'
    '[ext_resource type="Resource" path="res://data/moves/cadwyn_rust_slam.tres" id="20_phase2"]\n'
    '[ext_resource type="PackedScene" path="res://actors/enemies/Husk.tscn" id="21_add"]',
)
boss = boss.replace('[node name="Husk" type="CharacterBody3D"', '[node name="SerCadwyn" type="CharacterBody3D"')
boss = boss.replace('albedo_color = Color(0.45, 0.32, 0.28, 1)', 'albedo_color = Color(0.48, 0.24, 0.16, 1)')
boss = boss.replace("radius = 0.35\nheight = 1.7", "radius = 0.55\nheight = 2.6")
boss = boss.replace(
    'body = NodePath("Body")',
    'body = NodePath("Body")\n'
    'boss_id = "cadwyn"\n'
    'display_name = "Ser Cadwyn the Rusted"\n'
    "phase_thresholds = Array[float]([0.55])\n"
    'phase_movesets = Array[Resource]([ExtResource("20_phase2")])\n'
    'add_scene = ExtResource("21_add")\n'
    "adds_per_phase = 2\n"
    "transition_duration = 2.0",
)
# Cadwyn is bigger: lift the mesh and hitbox to match the 2.6 m capsule.
boss = boss.replace(
    "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.85, 0)",
    "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.3, 0)",
)
boss = boss.replace(
    "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.34, 1.35, 0)",
    "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.54, 2.1, 0)",
)
pathlib.Path("actors/bosses/SerCadwyn.tscn").write_text(boss, encoding="utf-8")
print("SerCadwyn.tscn written")

# ------------------------------------------------------------------ the arena
arena = '''[gd_scene load_steps=12 format=3]

[ext_resource type="Script" path="res://levels/level_root.gd" id="1_root"]
[ext_resource type="PackedScene" path="res://actors/player/Player.tscn" id="2_player"]
[ext_resource type="Script" path="res://actors/player/player_camera.gd" id="3_camera"]
[ext_resource type="Resource" path="res://data/tuning/tuning_camera.tres" id="4_camtuning"]
[ext_resource type="PackedScene" path="res://ui/hud/TouchControls.tscn" id="5_touch"]
[ext_resource type="Resource" path="res://data/biomes/mood_village.tres" id="6_mood"]
[ext_resource type="PackedScene" path="res://actors/bosses/SerCadwyn.tscn" id="7_cadwyn"]
[ext_resource type="Script" path="res://actors/bosses/fog_gate.gd" id="8_gate"]
[ext_resource type="Material" path="res://art/materials/mat_terrain.tres" id="9_terrain"]
[ext_resource type="Script" path="res://ui/hud/boss_health_bar.gd" id="10_bar"]
[ext_resource type="Script" path="res://ui/hud/damage_number_pool.gd" id="11_numbers"]

[sub_resource type="Environment" id="Env_arena"]
background_mode = 1
background_color = Color(0.12, 0.09, 0.08, 1)
ambient_light_source = 2
ambient_light_color = Color(0.45, 0.42, 0.5, 1)
ambient_light_energy = 0.5
fog_enabled = true
fog_light_color = Color(0.6, 0.4, 0.28, 1)
fog_density = 0.02

[sub_resource type="BoxShape3D" id="Shape_gate"]
size = Vector3(3, 8, 12)

[node name="CadwynArena" type="Node3D" node_paths=PackedStringArray("world_environment", "sun", "camera_rig")]
script = ExtResource("1_root")
starting_mood = ExtResource("6_mood")
world_environment = NodePath("Environment")
sun = NodePath("Sun")
camera_rig = NodePath("CameraRig")
level_id = "cadwyn_arena"

[node name="Environment" type="WorldEnvironment" parent="."]
environment = SubResource("Env_arena")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, -0.353553, 0.353553, 0, 0.707107, 0.707107, -0.5, -0.612372, 0.612372, 0, 14, 0)
light_energy = 1.3
light_color = Color(1, 0.72, 0.48, 1)
shadow_enabled = true
directional_shadow_max_distance = 45.0

[node name="Floor" type="CSGBox3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 24, -0.5, 0)
use_collision = true
size = Vector3(56, 1, 14)
material = ExtResource("9_terrain")

[node name="BackWall" type="CSGBox3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 24, 7, -7.5)
use_collision = true
size = Vector3(56, 18, 1)
material = ExtResource("9_terrain")

[node name="FarWall" type="CSGBox3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 51, 7, 0)
use_collision = true
size = Vector3(1, 18, 14)
material = ExtResource("9_terrain")

[node name="GateBarrier" type="StaticBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 3, 4, 0)

[node name="Shape" type="CollisionShape3D" parent="GateBarrier"]
shape = SubResource("Shape_gate")

[node name="FogVisual" type="CSGBox3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 3, 4, 0)
use_collision = false
size = Vector3(0.4, 8, 12)
material = ExtResource("9_terrain")

[node name="FogGate" type="Area3D" parent="." node_paths=PackedStringArray("barrier", "fog_visual")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 6, 4, 0)
collision_layer = 0
collision_mask = 2
script = ExtResource("8_gate")
boss_id = "cadwyn"
barrier = NodePath("../GateBarrier")
fog_visual = NodePath("../FogVisual")

[node name="Shape" type="CollisionShape3D" parent="FogGate"]
shape = SubResource("Shape_gate")

[node name="SerCadwyn" parent="." instance=ExtResource("7_cadwyn")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 38, 0.5, 0)

[node name="DamageNumbers" type="Node3D" parent="."]
script = ExtResource("11_numbers")
pool_size = 24

[node name="Player" parent="." instance=ExtResource("2_player")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 10, 0.4, 0)

[node name="CameraRig" type="Node3D" parent="." node_paths=PackedStringArray("target", "camera")]
script = ExtResource("3_camera")
target = NodePath("../Player")
tuning = ExtResource("4_camtuning")
camera = NodePath("Camera3D")

[node name="Camera3D" type="Camera3D" parent="CameraRig"]
transform = Transform3D(1, 0, 0, 0, 0.994522, 0.104528, 0, -0.104528, 0.994522, 0, 2.4, 8)
fov = 50.0

[node name="HUD" type="CanvasLayer" parent="."]

[node name="BossHealthBar" type="Control" parent="HUD"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("10_bar")

[node name="TouchControls" parent="HUD" instance=ExtResource("5_touch")]
'''
pathlib.Path("levels/biomes/cadwyn_arena.tscn").write_text(arena, encoding="utf-8")
print("cadwyn_arena.tscn written")
