extends EnemyMob

func hurt(amount: float, normal := Vector3.UP, knock := 0.0) -> void:
	var previous: Vector3 = rig.global_position
	super.hurt(amount, normal, knock)
	if level != null:
		var resolved: Vector3 = level.resolve_motion(previous, rig.global_position)
		rig.weapon_xf.origin += resolved-rig.global_position
		rig.global_position = resolved
