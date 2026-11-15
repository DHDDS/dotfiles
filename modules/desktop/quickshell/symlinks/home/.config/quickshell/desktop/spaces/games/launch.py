"""Shared game performance preferences, runners and Steam's launch wrapper."""

import json
import os
from pathlib import Path
import shlex
import shutil
import sqlite3
import sys

OVERLAYS = ('off', 'fps', 'detailed')
POSITIONS = ('top-left', 'top-right', 'bottom-left', 'bottom-right')
SIZES = {'small': 18, 'medium': 24, 'large': 32}
PERFORMANCE_DEFAULTS = {
    'overlay': 'off',
    'position': 'top-left',
    'size': 'medium',
    'fpsLimit': 0,
}
PERFORMANCE_KEYS = tuple(PERFORMANCE_DEFAULTS)
PROFILES = {
    'fps': 'fps_only',
    'detailed': 'fps,frametime,frame_timing,cpu_stats,gpu_stats,cpu_temp,gpu_temp,ram,vram',
}


def valid_proton(value):
    if not isinstance(value, str) or len(value) > 4096 or '\x00' in value:
        return False
    path = Path(value)
    return (
        path.is_absolute()
        and (path / 'proton').is_file()
        and os.access(path / 'proton', os.X_OK)
    )


def runners(env, roots, libraries, configured=''):
    home = Path(env.get('HOME', str(Path.home())))
    data = Path(env.get('XDG_DATA_HOME', home / '.local/share'))
    config = Path(env.get('XDG_CONFIG_HOME', home / '.config'))
    parents = [
        *(root / 'compatibilitytools.d' for root in roots),
        *(library / 'steamapps/common' for library in libraries),
        data / 'Steam/compatibilitytools.d',
        data / 'compatibilitytools.d',
        data / 'umu',
        config / 'heroic/tools/proton',
        home / '.var/app/com.heroicgameslauncher.hgl/config/heroic/tools/proton',
        Path('/usr/share/steam/compatibilitytools.d'),
    ]
    candidates = [Path(configured)] if configured else []
    for parent in parents:
        try:
            candidates.extend(sorted(parent.iterdir()))
        except OSError:
            continue
    found = {}
    for path in candidates:
        try:
            if valid_proton(str(path)):
                resolved = str(path.resolve())
                found[resolved] = {'id': resolved, 'name': path.name}
        except (OSError, ValueError):
            continue
    return [{'id': '', 'name': 'Automatic (UMU default)'}] + sorted(
        found.values(), key=lambda row: (row['name'].casefold(), row['id'])
    )


def performance_config(settings):
    overlay = settings.get('overlay', 'off')
    profile = PROFILES.get(overlay, 'no_display')
    return ','.join(
        (
            profile,
            f'position={settings.get("position", "top-left")}',
            f'font_size={SIZES.get(settings.get("size"), 24)}',
            f'fps_limit={int(settings.get("fpsLimit", 0))}',
        )
    )


def performance_environment(env, settings):
    env['MANGOHUD_CONFIG'] = performance_config(settings)
    enabled = (
        settings.get('overlay', 'off') != 'off' or int(settings.get('fpsLimit', 0)) > 0
    )
    env['MANGOHUD'] = '1' if enabled else '0'
    return enabled


def epic_wrapper(env, which, overlay, proton, umu, settings=None):
    """Return one Legendary wrapper string, preserving argument boundaries."""
    wrapper = [which('umu-run')] if umu else []
    if proton:
        if not umu or not valid_proton(proton):
            raise ValueError(
                'The selected Proton is unavailable. Choose another runner.'
            )
        env['PROTONPATH'] = proton
    elif umu:
        env.pop('PROTONPATH', None)
    preferences = {**PERFORMANCE_DEFAULTS, **(settings or {}), 'overlay': overlay}
    if performance_environment(env, preferences):
        executable = which('mangohud')
        if not executable:
            raise ValueError(
                'MangoHud is not installed. Turn the overlay off or install it.'
            )
        wrapper.insert(0, executable)
    return shlex.join(wrapper)


def read_preferences(env, store, external_id):
    home = Path(env.get('HOME', str(Path.home())))
    data = Path(env.get('XDG_DATA_HOME', home / '.local/share'))
    path = data / 'quickshell/desktop/spaces/games/library.sqlite'
    settings = dict(PERFORMANCE_DEFAULTS)
    if not path.is_file():
        return settings
    db = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=3)
    try:
        for scope in ('global', f'{store}:{external_id}'):
            row = db.execute(
                'SELECT value FROM launch_settings WHERE scope=?', (scope,)
            ).fetchone()
            if row:
                for key, value in json.loads(row[0]).items():
                    if key in PERFORMANCE_KEYS and value != 'inherit':
                        settings[key] = value
    finally:
        db.close()
    return settings


def main():
    if (
        len(sys.argv) < 5
        or sys.argv[1] != 'steam'
        or not sys.argv[2].isdigit()
        or sys.argv[3] != '--'
    ):
        raise SystemExit('Usage: launch.py steam APPID -- COMMAND [ARGUMENTS]')
    env = dict(os.environ)
    command = sys.argv[4:]
    # The separate gaming session already gives Steam its own Mangoapp overlay.
    if env.get('STEAM_USE_MANGOAPP') == '1':
        os.execvpe(command[0], command, env)
    settings = read_preferences(env, sys.argv[1], sys.argv[2])
    if performance_environment(env, settings):
        executable = shutil.which('mangohud')
        if not executable:
            raise SystemExit(
                'MangoHud is unavailable. Turn the overlay and frame limit off in Games settings.'
            )
        command.insert(0, executable)
    os.execvpe(command[0], command, env)


if __name__ == '__main__':
    main()
