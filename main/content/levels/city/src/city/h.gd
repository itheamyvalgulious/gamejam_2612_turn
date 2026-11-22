## Deterministic hash / noise helpers (CPU side).
class_name H
extends RefCounted

static func ih(x: int) -> int:
	x = ((x >> 16) ^ x) * 0x45d9f3b
	x = ((x >> 16) ^ x) * 0x45d9f3b
	x = (x >> 16) ^ x
	return x & 0x7fffffff

static func h2(a: int, b: int) -> int:
	return ih(a * 73856093 ^ b * 19349663)

static func h3(a: int, b: int, c: int) -> int:
	return ih(a * 73856093 ^ b * 19349663 ^ c * 83492791)

static func f(a: int, b: int, c: int = 0) -> float:
	return float(h3(a, b, c) % 100000) / 100000.0

## Random generator seeded from spatial / logical coordinates: the whole city is
## reproducible, and chunk streaming can rebuild identical content.
static func rng(a: int, b: int, c: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = h3(a, b, c)
	return r

static func pick(r: RandomNumberGenerator, arr: Array):
	return arr[r.randi() % arr.size()]

static func smoothstep(a: float, b: float, x: float) -> float:
	var t: float = clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)