extends EnemyMob
var nav_time := 0.0
var nav_path := PackedVector2Array()

func think(dt: float) -> void:
	if level != null and player != null and not level.melee_clear(center(),player.rig.global_position+Vector3(0,2.3,0)):
		attack_cd = maxf(attack_cd,dt+0.2)
	super.think(dt)
	if level != null:
		level.steer_enemy(self,dt)

func hurt(amount: float, normal := Vector3.UP, knock := 0.0) -> void:
	var previous: Vector3 = rig.global_position
	super.hurt(amount,normal,knock)
	if level != null:
		var resolved: Vector3 = level.resolve_motion(previous,rig.global_position,false)
		rig.weapon_xf.origin += resolved-rig.global_position
		rig.global_position = resolved
