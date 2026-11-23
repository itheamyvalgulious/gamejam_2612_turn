extends RefCounted
## The game supplies whether the Boss is visible from the player's camera.

enum Stage { SOLID, ENTERING, PHASED, RETURNING }

const CHARGE_TIME := 10.0
const LOOK_AWAY_GRACE := 0.15
const DRAIN_TIME := 12.0
const ENTER_TIME := 0.48
const ACTIVE_TIME := 24.0
const RETURN_TIME := 0.52
const RECHARGE_DELAY := 1.6

var stage := Stage.SOLID
var charge := 0.0
var age := 0.0
var _away := 0.0
var _recharge_lock := 0.0


func advance(delta: float, visible: bool, committed := false) -> void:
	var remaining := maxf(0.0, delta)
	while remaining > 0.000001:
		if stage == Stage.SOLID:
			if charge >= 1.0:
				if committed:
					return
				stage = Stage.ENTERING
				age = 0.0
			elif _recharge_lock > 0.0:
				var locked := minf(remaining, _recharge_lock)
				remaining -= locked
				_recharge_lock -= locked
			elif visible:
				_away = 0.0
				var step := minf(remaining, (1.0 - charge) * CHARGE_TIME)
				charge = minf(1.0, charge + step / CHARGE_TIME)
				remaining -= step
				if charge >= 0.999999:
					charge = 1.0
					if not committed:
						stage = Stage.ENTERING
						age = 0.0
			else:
				var grace := minf(remaining, maxf(0.0, LOOK_AWAY_GRACE - _away))
				_away += grace
				charge = maxf(0.0, charge - (remaining - grace) / DRAIN_TIME)
				return
		else:
			var duration := ENTER_TIME if stage == Stage.ENTERING else (ACTIVE_TIME if stage == Stage.PHASED else RETURN_TIME)
			var step := minf(remaining, duration - age)
			age += step
			remaining -= step
			if age >= duration - 0.000001:
				if stage == Stage.PHASED and committed:
					age = ACTIVE_TIME
					return
				age = 0.0
				match stage:
					Stage.ENTERING:
						stage = Stage.PHASED
						charge = 0.0
					Stage.PHASED:
						stage = Stage.RETURNING
					Stage.RETURNING:
						stage = Stage.SOLID
						_away = 0.0
						_recharge_lock = RECHARGE_DELAY - RETURN_TIME


func damage_multiplier(visible: bool) -> float:
	if stage == Stage.PHASED and age < ACTIVE_TIME:
		return 0.0
	return 0.20 if visible else 1.0
