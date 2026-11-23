import pathlib

OUT = pathlib.Path("levels/biomes/ashfall_village.tscn")


def box(name, parent, x, y, z, sx, sy, sz, collision="true"):
    p = 'parent="%s"' % parent if parent else 'parent="."'
    return (
        '\n[node name="%s" type="CSGBox3D" %s]\n'
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)\n"
        "use_collision = %s\n"
        "size = Vector3(%s, %s, %s)\n"
        'material = ExtResource("11_terrain")\n'
    ) % (name, p, x, y, z, collision, sx, sy, sz)


header = '''[gd_scene load_steps=20 format=3]

[ext_resource type="Script" path="res://levels/level_root.gd" id="1_root"]
[ext_resource type="PackedScene" path="res://actors/player/Player.tscn" id="2_player"]
[ext_resource type="Script" path="res://actors/player/player_camera.gd" id="3_camera"]
[ext_resource type="Resource" path="res://data/tuning/tuning_camera.tres" id="4_camtuning"]
[ext_resource type="PackedScene" path="res://ui/hud/TouchControls.tscn" id="5_touch"]
[ext_resource type="Resource" path="res://data/biomes/mood_village.tres" id="6_village"]
[ext_resource type="Script" path="res://actors/npc/wayshrine.gd" id="7_shrine"]
[ext_resource type="Script" path="res://levels/encounter_volume.gd" id="8_encounter"]
[ext_resource type="PackedScene" path="res://actors/enemies/Husk.tscn" id="9_husk"]
[ext_resource type="Script" path="res://levels/props/shortcut_gate.gd" id="10_gate"]
[ext_resource type="Material" path="res://art/materials/mat_terrain.tres" id="11_terrain"]
[ext_resource type="Script" path="res://levels/props/parallax_lane.gd" id="12_lane"]
[ext_resource type="Script" path="res://art/vfx/fog_card_field.gd" id="13_fog"]
[ext_resource type="Material" path="res://art/materials/mat_fog_card.tres" id="14_fogmat"]
[ext_resource type="Script" path="res://tools/prop_scatter.gd" id="15_scatter"]
[ext_resource type="Material" path="res://art/materials/mat_foliage.tres" id="16_foliage"]
[ext_resource type="Script" path="res://ui/hud/damage_number_pool.gd" id="17_numbers"]

[sub_resource type="Environment" id="Env_village"]
background_mode = 1
background_color = Color(0.16, 0.13, 0.11, 1)
ambient_light_source = 2
ambient_light_color = Color(0.45, 0.5, 0.6, 1)
ambient_light_energy = 0.55
fog_enabled = true
fog_light_color = Color(0.78, 0.54, 0.29, 1)
fog_density = 0.012

[sub_resource type="BoxShape3D" id="Shape_trigger"]
size = Vector3(5, 6, 10)

[sub_resource type="BoxShape3D" id="Shape_barrier"]
size = Vector3(3.5, 0.6, 12)

[sub_resource type="QuadMesh" id="Mesh_grass"]
size = Vector2(0.5, 0.6)

[node name="AshfallVillage" type="Node3D" node_paths=PackedStringArray("world_environment", "sun", "camera_rig")]
script = ExtResource("1_root")
starting_mood = ExtResource("6_village")
world_environment = NodePath("Environment")
sun = NodePath("Sun")
camera_rig = NodePath("CameraRig")
level_id = "ashfall_village"

[node name="Environment" type="WorldEnvironment" parent="."]
environment = SubResource("Env_village")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.906308, -0.271654, 0.32139, 0, 0.762127, 0.647386, -0.422618, -0.586715, 0.690253, 0, 14, 0)
light_energy = 1.6
light_color = Color(1, 0.78, 0.52, 1)
shadow_enabled = true
directional_shadow_max_distance = 45.0

[node name="Geometry" type="Node3D" parent="."]
'''

parts = [header]

# A switchback. The street runs east along the lower tier, climbs at the far end, then runs back
# WEST along an upper tier -- so the gatehouse ends up directly above the starting Wayshrine.
#
# This is the only shape that makes a shortcut mean anything in a 2.5D level. A passage from the far
# end back to the start is exactly as long as the walk it replaces; a loop that stacks the end above
# the beginning turns a 116 m round trip into a 9 m drop.
parts.append(box("StreetLower", "Geometry", 31, -0.5, 0, 66, 1, 12))
parts.append(box("ClimbLanding", "Geometry", 68, 2.0, 0, 10, 1, 12))
parts.append(box("ClimbUpper", "Geometry", 68, 5.5, 0, 10, 1, 12))
parts.append(box("StreetUpper", "Geometry", 36, 8.5, 0, 60, 1, 12))
parts.append(box("Gatehouse", "Geometry", 6, 8.5, 0, 12, 1, 12))

parts.append(box("BackWall", "Geometry", 36, 12, -6.5, 150, 34, 1))
parts.append(box("FrontLipLower", "Geometry", 36, 0.5, 6.2, 150, 3, 0.6))
parts.append(box("FrontLipUpper", "Geometry", 36, 9.5, 6.2, 150, 3, 0.6))
parts.append(box("EastWall", "Geometry", 74, 12, 0, 1, 34, 12))
parts.append(box("WestWallLower", "Geometry", -3, 4, 0, 1, 12, 12))
parts.append(box("WestWallUpper", "Geometry", -3, 12, 0, 1, 10, 12))

# The drop shaft: sealed until the gatehouse door is opened from above.
parts.append(box("ShaftWallEast", "Geometry", 12.6, 4.5, 0, 1.2, 9, 12))


# The gatehouse door. Sealed until opened from the upper tier; removing it drops the player straight
# down the shaft to the starting Wayshrine.
parts.append('''
[node name="ShortcutBarrier" type="StaticBody3D" parent="Geometry"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 9, 8.2, 0)

[node name="Mesh" type="CSGBox3D" parent="Geometry/ShortcutBarrier"]
use_collision = false
size = Vector3(3.5, 0.6, 12)
material = ExtResource("11_terrain")

[node name="Shape" type="CollisionShape3D" parent="Geometry/ShortcutBarrier"]
shape = SubResource("Shape_barrier")

[node name="ShortcutGate" type="Area3D" parent="." node_paths=PackedStringArray("barrier")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 9, 10, 0)
script = ExtResource("10_gate")
gate_id = "village_shortcut"
barrier = NodePath("../Geometry/ShortcutBarrier")
openable_from_x = 20.0
opens_from_right = false

[node name="Shape" type="CollisionShape3D" parent="ShortcutGate"]
shape = SubResource("Shape_trigger")
''')

# Depth lanes at the GDD's Z -6 / -14 / -40.
lanes = [
    ("LaneNear", -6.0, 0.15, 5.0, 120, 10),
    ("LaneMid", -14.0, 0.45, 11.0, 150, 20),
    ("LaneFar", -40.0, 0.80, 22.0, 240, 44),
]
for name, z, factor, y, sx, sy in lanes:
    parts.append(
        (
            '\n[node name="%s" type="Node3D" parent="."]\n'
            "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 34, 0, %s)\n"
            'script = ExtResource("12_lane")\n'
            "parallax_factor = %s\n"
            "affect_vertical = false\n"
            '\n[node name="Silhouette" type="CSGBox3D" parent="%s"]\n'
            "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n"
            "use_collision = false\n"
            "size = Vector3(%s, %s, 1)\n"
            'material = ExtResource("11_terrain")\n'
        )
        % (name, z, factor, name, y, sx, sy)
    )

for name, sid, x, y in [
    ("WayshrineGate", "village_gate", 5, 1),
    ("WayshrineSquare", "village_square", 62, 10),
]:
    parts.append(
        (
            '\n[node name="%s" type="Area3D" parent="."]\n'
            "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, 0)\n"
            "collision_layer = 128\ncollision_mask = 2\n"
            'script = ExtResource("7_shrine")\n'
            'shrine_id = "%s"\n'
            '\n[node name="Shape" type="CollisionShape3D" parent="%s"]\n'
            'shape = SubResource("Shape_trigger")\n'
            '\n[node name="Marker" type="CSGBox3D" parent="%s"]\n'
            "use_collision = false\nsize = Vector3(0.6, 2.4, 0.6)\n"
            'material = ExtResource("11_terrain")\n'
        )
        % (name, x, y, sid, name, name)
    )

encounters = [
    ("EncounterWell", "village_well", 26, 0.7, [(24, 0.7), (30, 0.7)]),
    ("EncounterSquare", "village_square_fight", 54, 0.7, [(50, 0.7), (55, 0.7), (60, 0.7)]),
    ("EncounterGatehouse", "village_gatehouse", 30, 9.7, [(26, 9.7), (32, 9.7), (38, 9.7)]),
]
for name, eid, x, y, markers in encounters:
    parts.append(
        (
            '\n[node name="%s" type="Area3D" parent="." node_paths=PackedStringArray("spawn_parent")]\n'
            "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, 0)\n"
            'script = ExtResource("8_encounter")\n'
            'encounter_id = "%s"\n'
            'enemy_scene = ExtResource("9_husk")\n'
            'spawn_parent = NodePath("Spawns")\n'
            "max_attackers = 2\nactivation_range = 26.0\nclear_once = false\n"
            '\n[node name="Spawns" type="Node3D" parent="%s"]\n'
        )
        % (name, x, y, eid, name)
    )
    for i, (mx, my) in enumerate(markers):
        parts.append(
            (
                '\n[node name="M%s" type="Marker3D" parent="%s/Spawns"]\n'
                "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, 0)\n"
            )
            % (i, name, mx - x, my - y)
        )

parts.append('''
[node name="StreetFog" type="MultiMeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 34, 0.5, 1)
script = ExtResource("13_fog")
card_count = 45
extents = Vector3(70, 4, 8)
size_min = 3.0
size_max = 7.0
card_material = ExtResource("14_fogmat")
seed_value = 5150

[node name="Grass" type="MultiMeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 20, 0.05, 2)
script = ExtResource("15_scatter")
prop_mesh = SubResource("Mesh_grass")
prop_material = ExtResource("16_foliage")
count = 220
extents = Vector3(60, 0, 7)
scale_min = 0.7
scale_max = 1.4
random_yaw = true
seed_value = 777

[node name="DamageNumbers" type="Node3D" parent="."]
script = ExtResource("17_numbers")
pool_size = 24

[node name="Player" parent="." instance=ExtResource("2_player")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 8, 0.4, 0)

[node name="CameraRig" type="Node3D" parent="." node_paths=PackedStringArray("target", "camera")]
script = ExtResource("3_camera")
target = NodePath("../Player")
tuning = ExtResource("4_camtuning")
camera = NodePath("Camera3D")

[node name="Camera3D" type="Camera3D" parent="CameraRig"]
transform = Transform3D(1, 0, 0, 0, 0.994522, 0.104528, 0, -0.104528, 0.994522, 0, 2.4, 8)
fov = 42.0

[node name="HUD" type="CanvasLayer" parent="."]

[node name="TouchControls" parent="HUD" instance=ExtResource("5_touch")]
''')

text = "".join(parts)
OUT.write_text(text, encoding="utf-8")
print("village written: %d nodes, %d lines" % (text.count("[node "), text.count("\n")))
