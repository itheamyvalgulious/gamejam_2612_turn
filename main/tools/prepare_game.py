"""Prepare the independently authored TURN scenes for a single Godot project."""

from pathlib import Path
import json
import re

from encounter_roster import adapt_host, adapt_wheel, adapters, pack_designs

MAIN = Path(__file__).resolve().parents[1]
REPO = MAIN.parent
OUTPUT = MAIN / "runtime"
ENEMIES = MAIN / "content/enemies"
MODULES = {
    "act": ("main/content/levels/actdemo", "Act"),
    "cargo": ("main/content/levels/cargo_hold2", "Cargo"),
    "city": ("main/content/levels/city", "City"),
    "galleria": ("main/content/levels/galleria", "Galleria"),
    "shadow_chamber": ("main/content/levels/shadow_chamber", "Fold"),
    "lab": ("main/content/levels/scene_lab", "Lab"),
}
TEXT = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc"}
ASSETS = {".ttf", ".otf", ".wav", ".ogg", ".png", ".jpg", ".webp", ".svg", ".obj", ".glb"}
FOLDERS = ("src", "assets", "gfx", "scripts", "shaders")
ENEMY_TYPES = {
    "encounter_unit.gd": "common",
    "arc_encounter.gd": "melee",
    "wheel_encounter.gd": "ranged",
    "shard_encounter.gd": "phase",
    "enemy_phase_boss.gd": "boss",
    "enemy_base.gd": "common",
    "enemy_mob.gd": "melee",
    "basic_enemy.gd": "melee",
    "enemy_archer.gd": "ranged",
    "archer_enemy.gd": "ranged",
    "phase_enemy.gd": "phase",
    "enemy_boss.gd": "boss",
}
PLAYER_FILES = {"camera.gd", "fp_viewmodel.gd", "player.gd"}
RESOURCE_PATH = re.compile(r'''(?<=["'])res://([^"'\s]+)(?=["'])''')
CLASS = re.compile(r"(?m)^class_name\s+(\w+)")
AUTOLOADS = re.compile(r'(?m)^(\w+)="\*res://([^"]+)"')
TOKEN = re.compile(r'#[^\n]*|""".*?"""|' + "'''.*?'''" +
                   r'|"(?:\\.|[^"\\])*"|' + r"'(?:\\.|[^'\\])*'|\b[A-Za-z_]\w*\b",
                   re.DOTALL)


def source_files(root, entry):
    paths = {root / entry}
    if (root / "main.tscn").is_file():
        paths.add(root / "main.tscn")
    for subdir in FOLDERS:
        paths.update(path for path in (root / subdir).rglob("*") if
                     path.is_file() and path.suffix.lower() in TEXT | ASSETS)
    pending = list(paths)
    for path in pending:
        if path.suffix in TEXT:
            text = path.read_text(encoding="utf-8-sig")
            for relative in re.findall(r'res://([^"\s]+\.(?:tscn|tres|gd))(?=")', text):
                candidate = root / relative
                if candidate.is_file() and candidate not in paths:
                    paths.add(candidate)
                    pending.append(candidate)
    yield from sorted(paths)


def content_path(episode, relative):
    """Keep each original implementation in its own folder within its category."""
    parts = relative.parts
    name = relative.name
    if parts[:2] == ("assets", "fonts"):
        if relative.suffix in {".ttf", ".otf"}:
            return Path("fonts/shared") / name
        return Path("fonts") / episode / name
    if parts[0] in {"gfx", "shaders"}:
        return Path("shaders") / episode / Path(*parts[1:])
    if relative.suffix.lower() in {".wav", ".ogg"}:
        return Path("audio") / episode / Path(*parts[1:])
    if parts[0] == "assets":
        return Path("media") / episode / Path(*parts[1:])
    if parts[0] != "src" or len(parts) == 2:
        return Path("levels") / episode / name

    folder = parts[1]
    remainder = Path(*parts[2:])
    if name in ENEMY_TYPES:
        return Path("enemies") / ENEMY_TYPES[name] / episode / remainder
    if folder == "fx" or name == "phase_fx.gd":
        return Path("vfx") / episode / remainder
    if folder == "ui" or name in {"hud.gd", "fp_mask.gd"}:
        return Path("ui") / episode / remainder
    if folder == "audio":
        return Path("audio") / episode / remainder
    if folder == "vesper":
        return Path("characters/vesper") / episode / remainder
    if folder == "game" and name in PLAYER_FILES:
        return Path("characters/player") / episode / remainder
    if folder == "core" or (folder == "game" and name != "level.gd"):
        return Path("systems") / episode / folder / remainder
    if folder == "game":
        return Path("levels") / episode / remainder
    return Path("levels") / episode / folder / remainder


def relocate_resources(text, episode, relative, destinations):
    def relocate(match):
        original = match[1]
        if original.startswith("team/"):
            return "res://runtime/enemies/designs/" + original.removeprefix("team/")
        destination = destinations.get(original)
        if destination is not None:
            return "res://runtime/" + destination.as_posix()
        # The map builders select a shader at runtime from these directories.
        if original.endswith("/") and original.startswith("gfx/"):
            generated = content_path(episode, Path(original) / "_")
            return "res://runtime/" + generated.parent.as_posix() + "/"
        raise ValueError(f"Unresolved resource in {episode}/{relative}: {original}")

    return RESOURCE_PATH.sub(relocate, text)


def scene_text(text, episode, names, autoloads, relative, destinations):
    if episode == "galleria" and relative.as_posix() == "src/encounter/neon_gi.gd":
        # Galleria inherited the city cache list, but contains no vehicle.
        text = text.replace('"res://src/encounter/vehicle.gd",', "")
    text = relocate_resources(text, episode, relative, destinations)
    if relative.suffix in {".tscn", ".tres"}:
        return re.sub(r'\s+uid="uid://[^"]+"', "", text)
    if relative.suffix != ".gd":
        return text

    singleton_names = {key: f"Turn{MODULES[episode][1]}Services.{key.lower()}" for key in autoloads}
    for key in tuple(singleton_names):
        # The geometry builder also has an array named P and the camera uses B in an equation.
        if re.search(rf"\b(?:var|const|func)\s+{key}\b", text):
            if re.search(rf"\b{key}\.", text) and key not in ("P", "B"):
                raise ValueError(f"Conflicting singleton in {relative}: {key}")
            if key == "B":
                text = re.sub(r"\bB\.(?=pressed\()", singleton_names[key] + ".", text)
            singleton_names.pop(key)
    identifiers = {**names, **singleton_names}
    text = TOKEN.sub(lambda match: identifiers.get(match[0], match[0]), text)
    text = text.replace("OS.get_cmdline_user_args()", "TurnSession.level_arguments()")
    text = text.replace("get_tree().quit()", "TurnSession.return_to_menu()")
    text = text.replace("退出游戏", "返回关卡选择")
    save_id = "fold" if episode == "shadow_chamber" else episode
    text = text.replace("user://actdemo_params.json", f"user://turn_{save_id}_params.json")
    if autoloads and relative.as_posix() == "src/main.gd":
        text, count = re.subn(
            r"(?m)^func next_level\(\) -> void:\n(?:\t[^\n]*(?:\n|$))+",
            "func next_level() -> void:\n\tTurnSession.advance_level()\n",
            text, count=1,
        )
        assert count == 1, (episode, relative)
    if episode == "act" and relative.as_posix() == "src/game/level.gd":
        local_transition = (
            "\t\t\t\tif index + 1 < LEVELS.size():\n"
            "\t\t\t\t\tstart_level(index + 1)\n"
            "\t\t\t\telse:\n"
            "\t\t\t\t\tstate = \"finished\"\n"
            "\t\t\t\t\tstate_t = 0.0"
        )
        assert local_transition in text
        text = text.replace(local_transition, '\t\t\t\tstate = "finished"\n\t\t\t\tstate_t = 0.0', 1)
    if relative.as_posix() in autoloads.values():
        key = next(key for key, value in autoloads.items() if value == relative.as_posix())
        text = f"class_name Turn{MODULES[episode][1]}{key}Service\n" + text
    return text


def services(prefix, autoloads):
    declarations, init, dispose = [], [], []
    for key in autoloads:
        field = key.lower()
        service_type = f"Turn{prefix}{key}Service"
        declarations.append(f"static var {field}: {service_type}")
        init.extend((f"\t{field} = {service_type}.new()", f"\troot.add_child({field})"))
        dispose.extend((f"\t{field}.free()", f"\t{field} = null"))
    disposal = [line for i in range(len(dispose) - 2, -1, -2) for line in dispose[i:i+2]]
    return "\n".join((f"class_name Turn{prefix}Services", "extends RefCounted", "",
                     *declarations, "", "", "static func start(root: Node) -> void:", *init,
                     "", "", "static func stop() -> void:", *disposal, ""))


def build():
    generated: dict[Path, bytes] = pack_designs(ENEMIES)
    for episode, (directory, prefix) in MODULES.items():
        root = REPO / directory
        project = (root / "project.godot").read_text(encoding="utf-8-sig")
        entry = re.search(r'(?m)^run/main_scene="res://([^"]+)"', project)[1]
        supplied = adapters(episode, ENEMIES)
        candidates = list(source_files(root, entry))
        candidates.extend(root / path for path in supplied)
        autoloads = dict(AUTOLOADS.findall(project))
        assert set(autoloads) == {"P", "B", "Fx", "Snd"}, (episode, autoloads)
        def read(relative):
            if relative.as_posix() in supplied:
                value = supplied[relative.as_posix()]
                return adapt_wheel(value) if relative.name == "wheel_encounter.gd" else value
            return (root / relative).read_text(encoding="utf-8-sig")

        names = {}
        for path in candidates:
            if path.suffix == ".gd":
                for name in CLASS.findall(read(path.relative_to(root))):
                    if name in names:
                        raise ValueError(f"Duplicate class in {episode}: {name}")
                    names[name] = f"Turn{prefix}{name}"
        destinations = {
            path.relative_to(root).as_posix(): content_path(episode, path.relative_to(root))
            for path in candidates
        }
        for path in candidates:
            relative = path.relative_to(root)
            destination = destinations[relative.as_posix()]
            if path.suffix in TEXT:
                source = adapt_host(episode, relative, read(relative), ENEMIES)
                transformed = scene_text(source, episode,
                                         names, autoloads, relative, destinations)
                data = transformed.encode("utf-8")
            else:
                data = path.read_bytes()
            if destination in generated and generated[destination] != data:
                raise ValueError(f"Different bytes for shared asset {destination}")
            generated[destination] = data
        destination = Path("systems") / episode / "services.gd"
        generated[destination] = services(prefix, autoloads).encode("utf-8")

    manifest = OUTPUT / ".files.json"
    old_paths = {Path(name) for name in json.loads(manifest.read_text())} if manifest.is_file() else set()
    for relative in old_paths - generated.keys():
        target = (OUTPUT / relative).resolve()
        if OUTPUT.resolve() in target.parents and target.is_file():
            target.unlink()
            for suffix in (".uid", ".import"):
                sidecar = target.with_name(target.name + suffix)
                if sidecar.is_file():
                    sidecar.unlink()
    for relative, raw in generated.items():
        target = OUTPUT / relative
        if not target.is_file() or target.read_bytes() != raw:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
    manifest.write_text(json.dumps(sorted(path.as_posix() for path in generated)), encoding="utf-8")
    print(f"Prepared {len(MODULES)} projects and {len(generated)} resources.")


if __name__ == "__main__":
    build()
