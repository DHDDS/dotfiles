"""Small, preserving edits to launcher-owned performance configuration."""

import json
from copy import deepcopy
import os
from pathlib import Path
import re
import shlex
import tempfile

from spaces.games import launch


def atomic_write(path, text, original=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            stream.write(text)
        if original is not None and path.read_text() != original:
            raise ValueError('The launcher changed its settings. Try again.')
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def running(names):
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            if (
                process.stat().st_uid == os.getuid()
                and (process / 'comm').read_text().strip() in names
            ):
                return True
        except OSError:
            continue
    return False


def _vdf_tree(text):
    pattern = re.compile(
        r'\s+|//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+'
    )
    tokens = [
        match
        for match in pattern.finditer(text)
        if not match[0].isspace() and not match[0].startswith(('//', '/*'))
    ]
    position = 0

    def take():
        nonlocal position
        if position >= len(tokens):
            raise ValueError('Incomplete Steam settings.')
        token = tokens[position]
        position += 1
        return token

    def decode(token):
        value = token[0]
        return (
            re.sub(r'\\([\\"])', r'\1', value[1:-1]) if value.startswith('"') else value
        )

    def node(nested):
        entries = {}
        while position < len(tokens):
            key = take()
            if key[0] == '}':
                if not nested:
                    raise ValueError('Invalid Steam settings.')
                return {'entries': entries, 'close': key.start()}
            if key[0] == '{':
                raise ValueError('Invalid Steam settings.')
            name = decode(key).casefold()
            if name in entries:
                raise ValueError(
                    'Duplicate Steam settings keys cannot be edited safely.'
                )
            value = take()
            if value[0] == '{':
                entries[name] = node(True)
            elif value[0] == '}':
                raise ValueError('Invalid Steam settings.')
            else:
                entries[name] = {
                    'value': decode(value),
                    'start': value.start(),
                    'end': value.end(),
                }
        if nested:
            raise ValueError('Incomplete Steam settings.')
        return {'entries': entries, 'close': len(text)}

    return node(False)


def _quoted(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def _emit(values, depth):
    result = ''
    for key, value in values.items():
        indent = '\t' * depth
        result += indent + _quoted(key)
        if isinstance(value, dict):
            result += '\n' + indent + '{\n' + _emit(value, depth + 1) + indent + '}\n'
        else:
            result += '\t\t' + _quoted(value) + '\n'
    return result


def steam_options(text, app_ids, wrapper):
    """Edit only LaunchOptions spans, retaining comments and unrelated VDF bytes."""
    tree = _vdf_tree(text)
    path = ('UserLocalConfigStore', 'Software', 'Valve', 'Steam', 'apps')
    node = tree
    for index, key in enumerate(path):
        child = node.get('entries', {}).get(key.casefold())
        if child is None:
            values = {
                app_id: {'LaunchOptions': _steam_option('', app_id, wrapper)}
                for app_id in app_ids
            }
            for key in reversed(path[index:]):
                values = {key: values}
            offset = node['close']
            return text[:offset] + '\n' + _emit(values, index) + text[offset:], len(
                app_ids
            )
        if 'entries' not in child:
            raise ValueError('Unsupported Steam settings structure.')
        node = child
    edits, additions, changed = [], {}, 0
    for app_id in app_ids:
        app = node['entries'].get(app_id)
        option = app.get('entries', {}).get('launchoptions') if app else None
        if app and 'entries' not in app or option and 'value' not in option:
            raise ValueError('Unsupported Steam launch options.')
        old = option['value'] if option else ''
        value = _steam_option(old, app_id, wrapper)
        if value == old:
            continue
        changed += 1
        if option:
            edits.append((option['start'], option['end'], _quoted(value)))
        elif app:
            edits.append(
                (
                    app['close'],
                    app['close'],
                    '\n' + _emit({'LaunchOptions': value}, len(path) + 1),
                )
            )
        else:
            additions[app_id] = {'LaunchOptions': value}
    if additions:
        edits.append((node['close'], node['close'], '\n' + _emit(additions, len(path))))
    for start, end, value in sorted(edits, reverse=True):
        text = text[:start] + value + text[end:]
    return text, changed


def _steam_option(old, app_id, wrapper):
    prefix = shlex.join([os.sys.executable, str(wrapper), 'steam', app_id, '--']) + ' '
    if prefix in old:
        return old
    if old.count('%command%') > 1 or any(char in old for char in '\n\r\x00'):
        raise ValueError(
            'Custom Steam launch options need manual review before enabling performance control.'
        )
    if '%command%' in old:
        before, after = old.split('%command%', 1)
        quote, escaped = '', False
        for char in before:
            if escaped:
                escaped = False
            elif char == '\\' and quote != "'":
                escaped = True
            elif quote and char == quote:
                quote = ''
            elif not quote and char in ('"', "'"):
                quote = char
        if (
            quote
            or escaped
            or before
            and not before[-1].isspace()
            or after
            and not after[0].isspace()
        ):
            raise ValueError(
                'Quoted or embedded Steam launch commands need manual review before enabling performance control.'
            )
        return old.replace('%command%', prefix + '%command%')
    return prefix + '%command%' + (' ' + old if old else '')


def steam_ready(text, app_id, wrapper):
    try:
        node = _vdf_tree(text)
        for key in (
            'UserLocalConfigStore',
            'Software',
            'Valve',
            'Steam',
            'apps',
            app_id,
            'LaunchOptions',
        ):
            node = node['entries'][key.casefold()]
        prefix = (
            shlex.join([os.sys.executable, str(wrapper), 'steam', app_id, '--']) + ' '
        )
        return prefix in node['value']
    except (ValueError, KeyError, TypeError):
        return False


def heroic_performance(root, app_id, settings, configure=True):
    path = Path(root) / 'GamesConfig' / (app_id + '.json')
    original = path.read_text() if path.exists() else None
    if original is not None and len(original) > 1024 * 1024:
        raise ValueError('Heroic game settings are too large to edit.')
    document = json.loads(original) if original is not None else {'version': 'v0.1'}
    if not isinstance(document, dict) or document.get('version', 'v0') not in (
        'v0',
        'v0.1',
    ):
        raise ValueError('This Heroic game settings format is not supported.')
    before = deepcopy(document)
    current = document.setdefault(app_id, {})
    if not isinstance(current, dict):
        raise ValueError('Heroic game settings could not be read.')
    environment = current.get('enviromentOptions')
    if environment is None:
        global_path = Path(root) / 'store/config.json'
        if global_path.exists():
            global_config = json.loads(global_path.read_text())
            global_settings = global_config.get(
                'settings', global_config.get('defaultSettings', {})
            )
            environment = global_settings.get('enviromentOptions', [])
    if environment is None:
        environment = []
    if not isinstance(environment, list) or any(
        not isinstance(entry, dict) for entry in environment
    ):
        raise ValueError('Heroic environment settings could not be read.')
    fields = {
        'MANGOHUD_CONFIG',
        'MANGOHUD_CONFIGFILE',
        'MANGOHUD',
        'QUICKSHELL_GAME_PERFORMANCE',
    }
    environment = [entry for entry in environment if entry.get('key') not in fields]
    performance_file = (
        Path(root) / 'GamesConfig/quickshell-performance' / (app_id + '.conf')
    )
    # Heroic caches settings in memory. The configured file path stays constant;
    # MangoHud reads fresh contents for each launched game, including hidden HUDs.
    current['showMangohud'] = True
    current['enviromentOptions'] = environment + [
        {'key': 'MANGOHUD_CONFIG', 'value': 'read_cfg'},
        {'key': 'MANGOHUD_CONFIGFILE', 'value': str(performance_file)},
        {'key': 'MANGOHUD', 'value': '1'},
        {'key': 'QUICKSHELL_GAME_PERFORMANCE', 'value': '1'},
    ]
    text = json.dumps(document, ensure_ascii=False, indent=2) + '\n'
    if document != before:
        if not configure:
            raise ValueError(
                'Quit Heroic, then enable GOG performance controls in Games settings.'
            )
        atomic_write(path, text, original)
    performance_text = launch.performance_config(settings).replace(',', '\n') + '\n'
    if (
        not performance_file.exists()
        or performance_file.read_text() != performance_text
    ):
        atomic_write(performance_file, performance_text)
    return True


def heroic_managed(root, app_id):
    try:
        data = json.loads((Path(root) / 'GamesConfig' / (app_id + '.json')).read_text())
        environment = data.get(app_id, {}).get('enviromentOptions', [])
        return any(
            entry.get('key') == 'QUICKSHELL_GAME_PERFORMANCE'
            for entry in environment
            if isinstance(entry, dict)
        ) and any(
            entry.get('key') == 'MANGOHUD_CONFIGFILE'
            and entry.get('value')
            == str(
                Path(root) / 'GamesConfig/quickshell-performance' / (app_id + '.conf')
            )
            for entry in environment
            if isinstance(entry, dict)
        )
    except (OSError, ValueError, AttributeError, TypeError):
        return False
