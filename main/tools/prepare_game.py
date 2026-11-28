"""Prepare the independently authored TURN scenes for a single Godot project."""

from pathlib import Path
import json
import re

from encounter_roster import adapt_duelist, adapt_host, adapt_wheel, adapters, dependencies, design_path, pack_designs

MAIN = Path(__file__).resolve().parents[1]
REPO = MAIN.parent
OUTPUT = MAIN / "runtime"
ENEMIES = MAIN / "content/enemies"
VESPER = MAIN / "content/characters/vesper"
VESPER_RUNTIME = Path("characters/vesper/design")
MODULES = {
    "act": ("main/content/levels/actdemo", "Act"),
    "cargo": ("main/content/levels/cargo_hold2", "Cargo"),
    "city": ("main/content/levels/city", "City"),
    "galleria": ("main/content/levels/galleria", "Galleria"),
    "shadow_chamber": ("main/content/levels/shadow_chamber", "Fold"),
    "room_shared": ("main/content/levels/shared", "Room"),
}
ROOM_LEVELS = ("warehouse", "panopticon", "ward", "hangar", "space_hull")
ROOM_AUTOLOADS = {
    "P": "src/core/params.gd",
    "B": "src/core/binds.gd",
    "Fx": "src/fx/vfx.gd",
    "Snd": "src/audio/audio.gd",
}
TEXT = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc"}
ASSETS = {".ttf", ".otf", ".wav", ".ogg", ".png", ".jpg", ".webp", ".svg", ".obj", ".glb"}
FOLDERS = ("src", "assets", "gfx", "scripts", "shaders")
ENEMY_PACKAGES = {
    "encounter_unit.gd": "shared",
    "arc_encounter.gd": "mobs/arc_sentinel",
    "duelist_encounter.gd": "mobs/mech_duelist",
    "wheel_encounter.gd": "mobs/wheel_sentry",
    "shard_encounter.gd": "mobs/shard_phantom",
    "enemy_phase_boss.gd": "bosses/phase_boss",
    "enemy_base.gd": "shared",
    "enemy_mob.gd": "mobs",
    "basic_enemy.gd": "mobs",
    "enemy_archer.gd": "mobs",
    "archer_enemy.gd": "mobs",
    "phase_enemy.gd": "mobs",
    "enemy_boss.gd": "bosses",
}
PLAYER_FILES = {"camera.gd", "player.gd"}
RESOURCE_PATH = re.compile(r'''(?<=["'])res://([^"'\s]+)(?=["'])''')
CLASS = re.compile(r"(?m)^class_name\s+(\w+)")
AUTOLOADS = re.compile(r'(?m)^(\w+)="\*res://([^"]+)"')
TOKEN = re.compile(r'#[^\n]*|""".*?"""|' + "'''.*?'''" +
                   r'|"(?:\\.|[^"\\])*"|' + r"'(?:\\.|[^'\\])*'|\b[A-Za-z_]\w*\b",
                   re.DOTALL)


def source_files(root, entry=None):
    paths = {root / entry} if entry is not None else set()
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
    if name in ENEMY_PACKAGES:
        return Path("enemies") / ENEMY_PACKAGES[name] / "encounters" / episode / remainder
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
        if original == "src/game/hud.gd" and relative.as_posix() == "src/main.gd":
            return "res://ui/hud/combat_hud.gd"
        if original.startswith("team/vesper/"):
            return "res://runtime/" + (VESPER_RUNTIME / original.removeprefix("team/vesper/")).as_posix()
        if original.startswith("team/"):
            design, path = original.removeprefix("team/").split("/", 1)
            return "res://runtime/" + design_path(design, path).as_posix()
        destination = destinations.get(original)
        if destination is not None:
            return "res://runtime/" + destination.as_posix()
        if original.startswith(("core/", "ui/", "assets/")) and (MAIN / original).is_file():
            # Shared project files resolve at the root after checking the module's own assets.
            return "res://" + original
        # The map builders select a shader at runtime from these directories.
        if original.endswith("/") and original.startswith("gfx/"):
            generated = content_path(episode, Path(original) / "_")
            return "res://runtime/" + generated.parent.as_posix() + "/"
        raise ValueError(f"Unresolved resource in {episode}/{relative}: {original}")

    return RESOURCE_PATH.sub(relocate, text)


def campaign_pause(text, binds):
    # The integrated game handles pause before sending input to the level.
    text = text.replace(
        '\telif event is InputEventKey and event.pressed and not event.echo:\n'
        '\t\tif event.keycode == KEY_ESCAPE:\n\t\t\t_open_pause()\n', "",
    )
    text = text.replace(f'\t\tif {binds}.just("pause"):\n\t\t\t_open_pause()\n', "")
    text, count = re.subn(r"(?m)^func _open_pause\(\) -> void:\n(?:\t[^\n]*\n)+\n\n", "", text)
    assert count == 1 and "_open_pause()" not in text
    if "func _capture_mouse()" in text:
        return text

    # Keep the module's hint and capture flag identical in both click and resume paths.
    capture = re.search(
        r'(?m)^\t\t\tInput.mouse_mode = Input.MOUSE_MODE_CAPTURED\n'
        r'\t\t\t_owns_mouse_capture = true\n\t\t\thud.set_hint\([^\n]*\)\n',
        text,
    )
    assert capture is not None
    capture_body = capture[0].replace("\t\t\t", "\t")
    text = text.replace(capture[0], "\t\t\t_capture_mouse()\n", 1)
    return text.replace(
        "func _menus_open() -> bool:",
        "func _capture_mouse() -> void:\n"
        "\tif not _mouse_capture_enabled or not get_window().has_focus():\n\t\treturn\n"
        + capture_body + "\n\nfunc _menus_open() -> bool:",
        1,
    )


def campaign_hud(text, episode, binds):
    text = re.sub(r'(?m)^\thud\.set_hint\("左键攻击[^\n]*\)\n', '', text)
    text = re.sub(r'(?m)^(\s*)hud\.set_hint\("左键攻击[^\n]*\)', r'\1hud.set_hint("")', text)
    text = text.replace('点击游戏画面控制视角 · Esc 暂停', '点击画面控制视角')
    text = text.replace('点击游戏画面继续 · Esc 暂停', '点击画面控制视角')
    text = text.replace('hud.set_hint(_level_hint)', 'hud.set_hint("")')
    text, count = re.subn(
        r'(?m)^\tlevel\.on_level_changed = func\([^\n]*\) -> void:\n'
        r'(?:\t{2}[^\n]*\n)*?\t\thud\.set_level\([^\n]*\)\n',
        '\tlevel.on_level_changed = func(_i: int, _name: String, _hint: String) -> void:\n'
        '\t\thud.set_level(TurnSession.active_level_index())\n',
        text, count=1,
    )
    assert count == 1, episode
    text = re.sub(r'(?m)^\t+hud\.show_banner\((?:"第 %d 关"|"CARGO HOLD 02"|level\.arena\[)[^\n]*\n', '', text)
    text = text.replace('\n\t\telse:\n\t\thud.clear_death()', '\n\t\thud.clear_death()')
    text = text.replace('hud.show_banner("第一人称视野黑幕", "你已经就在第一人称画面里 —— 按 V 切第三人称再看", 1.8)',
                        'hud.show_banner("视野遮罩仅用于第三人称", "", 1.4)')
    text = re.sub(r'(?m)^\telif level\.state == "finished" and _last_state != "finished":\n\t\thud\.show_banner\([^\n]*\)\n', '', text)
    clear = '\telif level.state == "clear" and _last_state != "clear":\n'
    assert clear in text, episode
    text = text.replace(clear, clear + '\t\tTurnSession.record_level_clear()\n', 1)
    text = re.sub(r'(?m)^var _block_banner_cd := [^\n]*\n|\t_block_banner_cd = [^\n]*\n', '', text)
    text, count = re.subn(r'(?ms)^\t\t\tif _block_banner_cd <= 0.0:\n.*?(?=^\t\t"\w)',
                          '', text, count=1)
    assert count == 1, episode
    text, count = re.subn(r'(?ms)^\tvar blocking := 0\n.*?^\t\thud\.set_state\(""\)\n',
                          '\thud.set_state("")\n', text, count=1)
    assert count == 1, episode
    hud_enemies = 'level.enemies if level.state == "fight" else []' if episode == "cargo" else "level.enemies"
    text = text.replace('hud.set_markers(level.build_markers())',
                        f'hud.update_threats({hud_enemies}, proj.items, cam.camera, player)')
    if episode == "room_shared":
        marker = '\thud.update_threats(level.enemies, proj.items, cam.camera, player)\n'
        text = text.replace(marker, marker + f'\thud.set_room_key({binds}.event_text("next_level"))\n', 1)
    text = text.replace('hud.set_state("弹反成功！")', 'hud.flash_reflect()')
    text = text.replace('\n\t\t"counter":\n\t\t\thud.set_state("它补射了一箭拦截！")', '')
    text = text.replace('\t\t"phase_immune":\n', '\t\t"phase_immune":\n\t\t\thud.flash_immune()\n')
    return text


def manual_retry(text, params):
    delay = f'{params}.getf("rules.death_delay")'
    text = re.sub(r'\telif state == "dead" and state_t > ' + re.escape(delay) + r':\n\t\tstart_level\(0\)\n', '', text)
    return re.sub(r'(\t\t"dead":\n)\t\t\tif state_t > ' + re.escape(delay) + r':\n\t\t\t\tstart_level\([^\n]*\)\n',
                  r'\1\t\t\tpass\n', text)


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
    save_id = {"shadow_chamber": "fold", "room_shared": "lab"}.get(episode, episode)
    text = text.replace("user://actdemo_params.json", f"user://turn_{save_id}_params.json")
    if autoloads and relative.as_posix() == "src/main.gd":
        text = campaign_pause(text, singleton_names["B"])
        text = campaign_hud(text, episode, singleton_names["B"])
        text, count = re.subn(
            r"(?m)^func next_level\(\) -> void:\n(?:\t[^\n]*(?:\n|$))+",
            "func next_level() -> void:\n\tTurnSession.advance_level()\n",
            text, count=1,
        )
        assert count == 1, (episode, relative)
    if relative.name == "level.gd":
        text = manual_retry(text, singleton_names["P"])
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
        # Detaching runs _exit_tree, allowing audio services to join their
        # prewarm thread before Godot destroys the node.
        dispose.append((f"\t{field}.get_parent().remove_child({field})",
                        f"\t{field}.queue_free()", f"\t{field} = null"))
    disposal = [line for block in reversed(dispose) for line in block]
    return "\n".join((f"class_name Turn{prefix}Services", "extends RefCounted", "",
                     *declarations, "", "", "static func start(root: Node) -> void:", *init,
                     "", "", "static func stop() -> void:", *disposal, ""))


def build():
    generated: dict[Path, bytes] = pack_designs(ENEMIES, MAIN)
    for relative, data in dependencies(VESPER, ["integration/campaign_rig.gd"], MAIN):
        if isinstance(data, str):
            data = RESOURCE_PATH.sub(
                lambda match: "res://runtime/" + (VESPER_RUNTIME / match[1]).as_posix(),
                data,
            ).encode("utf-8")
        generated[VESPER_RUNTIME / relative] = data
    for episode, (directory, prefix) in MODULES.items():
        root = REPO / directory
        if episode == "room_shared":
            autoloads = ROOM_AUTOLOADS
            sources = {path.relative_to(root): path for path in source_files(root)}
            for room in ROOM_LEVELS:
                room_root = root.parent / room
                for path in source_files(room_root, "main.tscn"):
                    sources[Path(room) / path.relative_to(room_root)] = path
        else:
            project = (root / "project.godot").read_text(encoding="utf-8-sig")
            entry = re.search(r'(?m)^run/main_scene="res://([^"]+)"', project)[1]
            autoloads = dict(AUTOLOADS.findall(project))
            sources = {path.relative_to(root): path for path in source_files(root, entry)}
        supplied = adapters(episode, ENEMIES)
        sources.update((Path(path), root / path) for path in supplied)
        assert set(autoloads) == {"P", "B", "Fx", "Snd"}, (episode, autoloads)
        def read(relative):
            if relative.as_posix() in supplied:
                value = supplied[relative.as_posix()]
                if relative.name == "wheel_encounter.gd":
                    return adapt_wheel(value)
                if relative.name == "duelist_encounter.gd":
                    return adapt_duelist(value)
                return value
            return sources[relative].read_text(encoding="utf-8-sig")

        names = {}
        for relative in sources:
            if relative.suffix == ".gd":
                for name in CLASS.findall(read(relative)):
                    if name in names:
                        raise ValueError(f"Duplicate class in {episode}: {name}")
                    names[name] = f"Turn{prefix}{name}"
        destinations = {}
        for relative in sources:
            first, *rest = relative.parts
            if episode == "room_shared" and first in ROOM_LEVELS:
                destinations[relative.as_posix()] = content_path(first, Path(*rest))
            else:
                destinations[relative.as_posix()] = content_path(episode, relative)
        for relative, path in sources.items():
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
    print(f"Prepared {len(MODULES) - 1 + len(ROOM_LEVELS)} scene modules and {len(generated)} resources.")


if __name__ == "__main__":
    build()
