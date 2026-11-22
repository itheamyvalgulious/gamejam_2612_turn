extends EnemyArcher
var nav_time := 0.0
var nav_path := PackedVector2Array()

func think(dt: float) -> void:
	super.think(dt)
	if level != null and draw_t<=0:
		level.steer_enemy(self,dt,true)

func _fire() -> void:
	if level != null and not level.melee_clear(fire_origin(),player.rig.global_position+Vector3(0,2.3,0)):
		return
	super._fire()

func hurt(amount: float, normal := Vector3.UP, knock := 0.0) -> void:
	var previous: Vector3 = rig.global_position
	super.hurt(amount,normal,knock)
	if level != null:
		var resolved: Vector3 = level.resolve_motion(previous,rig.global_position,false)
		rig.weapon_xf.origin += resolved-rig.global_position
		rig.global_position = resolved
