extends EnemyMob
## A stationary phase guard. Only Level.choose_phase_point may move it.
var anchor_index := 0
var phase_cooldown := 0.0
var teleport_count := 0

func setup_phase() -> void:
	setup_mob({"tag": "encounter_phase", "accent": Color("bf80ff"), "tint": Color(0.81,0.86,1.0), "metal_mix": 0.45})
	kind = "phase"

func blocks_when_seen() -> bool:
	return false

func think(dt: float) -> void:
	phase_cooldown = maxf(0, phase_cooldown-dt)
	attack_cd = maxf(0, attack_cd-dt)
	rig.move_command = Vector3.ZERO
	face_player()
	if level.state != "fight" or not player.alive:
		return
	# First sight has zero delay. Arrival grants 1.35 s of vulnerability;
	# otherwise an always-visible target would teleport every frame forever.
	if phase_cooldown <= 0.0 and level.phase_visible(self):
		var next: int = level.choose_phase_point(self)
		if next >= 0:
			var old: Vector3 = rig.global_position
			anchor_index = next
			global_position = level.arena["anchors"][next]
			rig.reset_demo(Vector3.ZERO, rig.heading)
			attack_cd = 0.35
			phase_cooldown = 1.35
			teleport_count += 1
			level.show_phase(old, rig.global_position)
			return
	# Stay on the pad and attack only when the player enters melee reach.
	if not rig.is_attacking and attack_cd <= 0 and dist_to_player() <= P.getf("mob.attack_range"):
		var w := P.getf("mob.windup")
		var a := P.getf("mob.active")
		var r := P.getf("mob.recovery")
		rig.set_timings({"mob": {"duration": w+a+r, "windup": w, "active": a, "recovery": r}})
		rig.timing_key = "mob"
		swung_serial += 1
		rig.force_attack("light", 0.0, 0.0)
		attack_cd = w+a+r+0.4

func hurt(amount: float, normal := Vector3.UP, _knock := 0.0) -> void:
	# Fixed pads are authoritative, including after parries or knockback.
	super.hurt(amount, normal, 0.0)

func step(dt: float, ctx: Dictionary) -> void:
	var before := teleport_count
	super.step(dt, ctx)
	if before != teleport_count:
		# Never sweep a sword hitbox across the teleport path.
		rig.weapon_prev_xf = rig.weapon_xf
