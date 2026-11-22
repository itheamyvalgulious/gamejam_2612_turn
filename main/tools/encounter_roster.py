"""Reusable enemy dependencies for the campaign."""

from pathlib import Path
import re

ROOTS = {
    "fold": ("boss/phase_boss", ["src/enemies/phase_boss/phase_boss_combat.gd"]),
    "arc": ("melee/arc_sentinel", ["scripts/ch/arc_sentinel.gd"]),
    "shard": ("phase/shard_phantom", ["scripts/character.gd", "scripts/phantom/energy_shuriken.gd"]),
    "wheel": ("ranged/wheel_sentry", ["scenes/ranged/wheel_sentry_model.tscn", "src/enemies/ranged/wheel_sentry_beam.gd"]),
}
PATHS = re.compile(r'''(?<=["'])res://([^"'\s]+)(?=["'])''')


def dependencies(directory, roots):
    pending = list(roots)
    seen = set()
    while pending:
        item = pending.pop()
        if item in seen:
            continue
        seen.add(item)
        file = directory / item
        if not file.exists():
            raise FileNotFoundError(file)
        if file.suffix in {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc"}:
            text = file.read_text(encoding="utf-8-sig")
            if item.endswith("wheel_sentry_beam.gd"):
                text = re.sub(r"(?m)^const ArenaKit = preload\(.+\)\n", "", text)
                text = text.replace("ArenaKit.BALL", "1.2")
            pending.extend(PATHS.findall(text))
        else:
            text = None
        yield item, text if text is not None else file.read_bytes()


def pack_designs(enemies):
    generated = {}
    for design, (directory, roots) in ROOTS.items():
        for path, value in dependencies(enemies / directory, roots):
            dest = Path("enemies/designs") / design / path
            if isinstance(value, str):
                value = PATHS.sub(lambda m: "res://runtime/enemies/designs/" + design + "/" + m[1], value)
                if dest.suffix in {".tscn", ".tres"}:
                    value = re.sub(r'\s+uid="uid://[^"]+"', "", value)
                value = value.encode("utf-8")
            generated[dest] = value
    return generated


def adapters(episode, enemies):
    if episode not in {"act", "cargo", "city", "galleria"}:
        return {}
    bindings = {
        "src/game/encounter_unit.gd": "shared/encounter_unit.gd",
        "src/game/arc_encounter.gd": "melee/arc_encounter.gd",
    }
    if episode in {"act", "city", "galleria"}:
        bindings["src/game/wheel_encounter.gd"] = "ranged/wheel_sentry/src/enemies/ranged/wheel_sentry_enemy.gd"
    if episode in {"cargo", "city"}:
        bindings["src/game/shard_encounter.gd"] = "phase/shard_encounter.gd"
    return {path: (enemies / source).read_text(encoding="utf-8-sig") for path, source in bindings.items()}


def adapt_wheel(text):
    text = text.replace("extends EnemyUnit", 'extends "res://src/game/encounter_unit.gd"')
    for path in ("scenes/ranged/wheel_sentry_model.tscn", "src/enemies/ranged/wheel_sentry_beam.gd"):
        text = text.replace("res://" + path, "res://team/wheel/" + path)
    text = text.replace('kind = "archer"', 'kind = "archer"\n\tenemy_id = "wheel_sentry"')
    return text


def adapt_host(episode, relative, text, enemies):
    if relative.as_posix() == "src/game/projectiles.gd" and episode in {"cargo", "city"}:
        text += """

func spawn_shard(pos: Vector3, direction: Vector3, speed: float, damage: float) -> Dictionary:
    var node := MeshInstance3D.new()
    node.mesh = preload("res://team/shard/scripts/phantom/phantom_kit.gd").shuriken_mesh(4, 0.48, 0.21, 0.06)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#ffae62")
    material.emission = Color("#ff751f")
    material.emission_enabled = true
    material.emission_energy_multiplier = 3.0
    node.material_override = material
    return _add(node, pos, direction * speed, 0.32, damage, "qi", "enemy")
""".replace("    ", "\t")
    if episode not in {"act", "city", "galleria"}:
        return text
    wheel = enemies / "ranged/wheel_sentry"
    relative = relative.as_posix()
    additions = {
        "src/fx/vfx.gd": ["sentry_bolt_flash"],
        "src/audio/audio.gd": ["set_loop_mix"],
    }
    if relative in additions:
        source = (wheel / relative).read_text(encoding="utf-8-sig")
        for name in additions[relative]:
            if not re.search(rf"(?m)^func {name}\(", text):
                chunk = function(source, name)
                if name == "set_loop_mix" and "var base_rate" not in text:
                    text = text.replace("\tvar rate := 1.0", "\tvar base_rate := 1.0\n\tvar rate := 1.0", 1)
                    text = text.replace('v.rate = float(opts.get("rate", 1.0))', 'v.base_rate = float(opts.get("rate", 1.0))\n\tv.rate = v.base_rate')
                    text = text.replace("v.rate = clampf(lerpf(", "v.rate = v.base_rate * clampf(lerpf(")
                    chunk = chunk.replace("v.base_rate = rate", "v.base_rate = rate\n\tv.rate = rate")
                text += "\n\n" + chunk + "\n"
    if relative == "src/audio/synth.gd":
        source = (wheel / relative).read_text(encoding="utf-8-sig")
        begin = source.index('\t\t"sentry_charge":')
        end = source.index('\t\t"laser":', begin)
        text = text.replace('\t\t"laser":', source[begin:end] + '\t\t"laser":', 1)
    if relative == "src/core/params.gd":
        source = (wheel / relative).read_text(encoding="utf-8-sig")
        specs = [line for line in source.splitlines() if re.match(r'\s*_f\("sentry\.', line)]
        point = next(line for line in text.splitlines() if re.match(r'\s*_f\("archer\.hp"', line))
        text = text.replace(point, "\n".join(specs + [point]), 1)
    if relative == "src/game/projectiles.gd":
        source = (wheel / relative).read_text(encoding="utf-8-sig")
        for name in ("spawn_arrow", "spawn_interceptor", "_reflect"):
            text = text.replace(function(text, name), function(source, name))
        text = text.replace('"被箭射穿" if String(it["kind"]) == "arrow" else "被刀气切开"', '"被小激光束击中" if bool(it.get("beam_bolt", false)) else "被 Shard Phantom 击中"')
    return text


def function(text, name):
    match = re.search(rf"(?ms)^(?:static )?func {name}\(.*?(?=^\S|\Z)", text)
    if not match:
        raise ValueError(f"Missing function: {name}")
    return match[0].rstrip()
