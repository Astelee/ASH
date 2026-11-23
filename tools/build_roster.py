"""Generate the Phase 6 enemy roster as .tres data.

Every value comes from the tables in docs/GDD.md section 9. Adding a variant means adding a row
here, never a script -- which is the whole point of the data-driven design in CLAUDE.md section 1.
"""

import pathlib

MOVE = '''[gd_resource type="Resource" script_class="AttackMove" load_steps=2 format=3]

[ext_resource type="Script" path="res://combat/attack_move.gd" id="1_move"]

[resource]
script = ExtResource("1_move")
anim = &"{anim}"
windup = {windup}
active = {active}
recovery = {recovery}
combo_window = 0.0
charge_max = 0.0
charge_multiplier = 1.8
damage_multiplier = {dmg}
poise_damage = {poise}
stamina_cost = 0.0
guaranteed_poise_break = {breaks}
hitbox_offset = Vector3({offx}, 1.0, 0)
hitbox_size = Vector3({sizex}, 1.2, 1.0)
lunge_speed = {lunge}
'''

STATS = '''[gd_resource type="Resource" script_class="StatBlock" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/stats/stat_block.gd" id="1_stats"]

[resource]
script = ExtResource("1_stats")
vigor = 0
endurance = 0
might = 0
finesse = 0
ember_bound = 0
health_base = {hp}
health_per_vigor = 0.0
stamina_base = 100.0
stamina_per_endurance = 0.0
stamina_regen_base = 12.0
stamina_regen_per_endurance = 0.0
stamina_regen_delay = 1.0
'''

WEAPON = '''[gd_resource type="Resource" script_class="WeaponData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/items/weapon_data.gd" id="1_weapon"]

[resource]
script = ExtResource("1_weapon")
display_name = "{name}"
base_damage = {base}
damage_type = {dtype}
moveset_id = &"{mid}"
weight = 6.0
scaling_might = 0
'''


def write(path, text):
    p = pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


# ---------------------------------------------------------------- moves
moves = [
    # file, anim, windup, active, recovery, dmg, poise, breaks, offx, sizex, lunge
    ("cultist_throw", "attack_throw", 0.70, 0.05, 0.60, 1.0, 10.0, "false", 0.8, 1.0, 0.0),
    ("warden_thrust", "attack_thrust", 0.55, 0.10, 0.70, 1.15, 30.0, "false", 1.5, 2.2, 2.0),
    ("warden_bash", "attack_bash", 0.40, 0.10, 0.55, 0.85, 45.0, "false", 1.1, 1.4, 1.4),
    ("wretch_lunge", "attack_lunge", 0.05, 0.30, 0.45, 0.9, 8.0, "false", 0.7, 1.3, 0.0),
    ("bell_swing", "attack_swing", 0.60, 0.12, 0.65, 1.1, 26.0, "false", 1.1, 1.7, 1.0),
    ("cadwyn_cleave", "attack_cleave", 0.70, 0.14, 0.70, 1.25, 40.0, "false", 1.4, 2.4, 2.4),
    ("cadwyn_rust_slam", "attack_slam", 0.85, 0.16, 0.80, 1.6, 999.0, "true", 1.2, 3.2, 1.6),
]
for f, anim, w, a, r, dmg, poise, breaks, offx, sizex, lunge in moves:
    write(
        "data/moves/%s.tres" % f,
        MOVE.format(
            anim=anim, windup=w, active=a, recovery=r, dmg=dmg, poise=poise,
            breaks=breaks, offx=offx, sizex=sizex, lunge=lunge,
        ),
    )

# ---------------------------------------------------------------- stat blocks
for f, hp in [
    ("cultist_stats", 90.0),
    ("warden_stats", 260.0),
    ("wretch_stats", 55.0),
    ("bell_stats", 340.0),
    ("cadwyn_stats", 1450.0),
]:
    write("data/stats/%s.tres" % f, STATS.format(hp=hp))

# ---------------------------------------------------------------- weapons
for f, name, base, dtype, mid in [
    ("cultist_flask", "Rot Flask", 22.0, 2, "cultist"),
    ("warden_spear", "Warden Spear", 34.0, 0, "warden"),
    ("wretch_claws", "Gravewretch Claws", 18.0, 0, "wretch"),
    ("bell_maul", "Bell-Bearer Maul", 38.0, 0, "bell"),
    ("cadwyn_greatsword", "Rusted Greatsword", 52.0, 0, "cadwyn"),
]:
    write("data/items/%s.tres" % f, WEAPON.format(name=name, base=base, dtype=dtype, mid=mid))

# ---------------------------------------------------------------- enemies
ENEMY_HEAD = '''[gd_resource type="Resource" script_class="EnemyData" load_steps={steps} format=3]

[ext_resource type="Script" path="res://data/enemies/enemy_data.gd" id="1_enemy"]
[ext_resource type="Resource" path="res://data/stats/{stats}.tres" id="2_stats"]
[ext_resource type="Resource" path="res://data/items/{weapon}.tres" id="3_weapon"]
'''

roster = [
    dict(
        file="enemy_crow_mask", stats="cultist_stats", weapon="cultist_flask",
        name="Crow-Mask Cultist", poise=25.0, defense=18.0, embers=175,
        rp=0.0, rf=0.0, rr=0.5, rh=0.0,
        moves=["cultist_throw"], speed=2.2, detect=16.0, attack=9.0, repos=8.0, recover=0.9,
        extra=(
            "is_ranged = true\n"
            'projectile_scene = ExtResource("4_projectile")\n'
            "retreat_range = 5.5\n"
        ),
        projectile=True,
    ),
    dict(
        file="enemy_warden", stats="warden_stats", weapon="warden_spear",
        name="Warden", poise=95.0, defense=46.0, embers=400,
        rp=0.4, rf=-0.25, rr=0.0, rh=0.0,
        moves=["warden_thrust", "warden_bash"], speed=1.5, detect=13.0, attack=2.6,
        repos=4.0, recover=0.75,
        extra="shield_absorption = 0.8\n",
    ),
    dict(
        file="enemy_gravewretch", stats="wretch_stats", weapon="wretch_claws",
        name="Gravewretch", poise=15.0, defense=12.0, embers=60,
        rp=0.0, rf=0.0, rr=0.0, rh=-0.5,
        moves=["wretch_lunge"], speed=3.4, detect=18.0, attack=5.5, repos=3.0, recover=0.5,
        extra="lunges_from_offscreen = true\nlunge_speed = 9.5\n",
    ),
    dict(
        file="enemy_bell_bearer", stats="bell_stats", weapon="bell_maul",
        name="Bell-Bearer", poise=120.0, defense=40.0, embers=900,
        rp=0.3, rf=0.0, rr=0.0, rh=0.0,
        moves=["bell_swing"], speed=1.4, detect=20.0, attack=2.4, repos=5.0, recover=0.9,
        extra="aura_radius = 12.0\naura_damage_bonus = 0.35\n",
    ),
    dict(
        file="boss_cadwyn", stats="cadwyn_stats", weapon="cadwyn_greatsword",
        name="Ser Cadwyn the Rusted", poise=180.0, defense=52.0, embers=4500,
        rp=0.25, rf=-0.3, rr=0.0, rh=0.0,
        moves=["cadwyn_cleave"], speed=2.0, detect=22.0, attack=3.0, repos=5.0, recover=0.7,
        extra="",
    ),
]

for e in roster:
    steps = 5 if e.get("projectile") else 4
    head = ENEMY_HEAD.format(steps=steps, stats=e["stats"], weapon=e["weapon"])
    if e.get("projectile"):
        head += '[ext_resource type="PackedScene" path="res://combat/RotFlask.tscn" id="4_projectile"]\n'
    move_ids = []
    for i, m in enumerate(e["moves"]):
        rid = "5_move%d" % i
        head += '[ext_resource type="Resource" path="res://data/moves/%s.tres" id="%s"]\n' % (m, rid)
        move_ids.append(rid)
    array = ", ".join('ExtResource("%s")' % r for r in move_ids)
    body = (
        '\n[resource]\nscript = ExtResource("1_enemy")\n'
        'display_name = "%s"\n'
        'stats = ExtResource("2_stats")\n'
        "max_poise = %s\ndefense = %s\nember_drop = %s\n"
        "resist_physical = %s\nresist_fire = %s\nresist_rot = %s\nresist_holy = %s\n"
        "moveset = Array[Resource]([%s])\n"
        'weapon = ExtResource("3_weapon")\n'
        "move_speed = %s\ndetect_range = %s\nattack_range = %s\n"
        "reposition_range = %s\nrecover_time = %s\n%s"
    ) % (
        e["name"], e["poise"], e["defense"], e["embers"],
        e["rp"], e["rf"], e["rr"], e["rh"], array,
        e["speed"], e["detect"], e["attack"], e["repos"], e["recover"], e["extra"],
    )
    # load_steps must count every ext_resource plus the resource itself.
    total = head.count("[ext_resource") + 1
    head = head.replace("load_steps=%d" % steps, "load_steps=%d" % total)
    write("data/enemies/%s.tres" % e["file"], head + body)

print("roster written: %d moves, %d enemies" % (len(moves), len(roster)))
