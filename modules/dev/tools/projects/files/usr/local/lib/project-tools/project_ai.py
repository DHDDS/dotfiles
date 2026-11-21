"""Connect Project Tools to the local Lemonade service."""

import http.client
import json
import os
import subprocess
import time
from pathlib import Path

UNIT = 'lemond.service'
HOST = 'localhost'
KEY_NAMES = ('LEMONADE_API_KEY', 'LEMONADE_ADMIN_API_KEY')


def systemctl(*args, user=False):
    return subprocess.run(
        ['systemctl', *(['--user'] if user else []), *args, UNIT],
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )


def system_service_active():
    try:
        return systemctl('is-active').stdout.strip() in (
            'active',
            'activating',
            'deactivating',
        )
    except (OSError, subprocess.TimeoutExpired):
        return False


def connection(system):
    if system:
        config = Path('/var/lib/lemonade/.config/lemonade')
    else:
        config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
        config /= 'lemonade'
    try:
        port = json.loads((config / 'config.json').read_text())['port']
    except (OSError, ValueError, TypeError, KeyError):
        port = 13305
    if type(port) is not int or not 1 <= port <= 65535:
        raise ValueError('Invalid Lemonade port.')

    keys = {name: os.environ[name] for name in KEY_NAMES if os.environ.get(name)}
    if not system:
        try:
            lines = (config / 'lemond.conf').read_text().splitlines()
        except (OSError, ValueError):
            lines = []
        for line in lines:
            name, _, value = line.strip().partition('=')
            if len(value) > 1 and value[0] == value[-1] and value[0] in '"\'':
                value = value[1:-1]
            if name in KEY_NAMES and value:
                keys.setdefault(name, value)
    return port, keys


def chat_models(port, keys):
    key = next((keys[name] for name in KEY_NAMES if name in keys), '')
    headers = {'Authorization': f'Bearer {key}'} if key else {}
    # A direct loopback connection avoids HTTP proxies and redirects.
    conn = http.client.HTTPConnection(HOST, port, timeout=2)
    try:
        conn.request('GET', '/v1/models', headers=headers)
        with conn.getresponse() as response:
            if response.status != 200:
                raise ValueError(f'Lemonade returned HTTP {response.status}.')
            rows = json.load(response)['data']
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        raise ValueError(
            'Invalid response from the Lemonade models endpoint.'
        ) from error
    finally:
        conn.close()

    models = set()
    for row in rows:
        model = row['id']
        recipe = row.get('recipe', '')
        if (
            model
            and 'chat' in row.get('labels', [])
            and recipe != 'cloud'
            and not recipe.startswith('collection.')
        ):
            models.add(model)
    return sorted(models, key=str.casefold)


def lemonade_status(start=False):
    system = system_service_active()
    try:
        port, keys = connection(system)
        try:
            return dict(models=chat_models(port, keys), can_start=False, message='')
        except (OSError, http.client.HTTPException):
            pass

        if system:
            return dict(
                models=None,
                can_start=False,
                message='The system Lemonade service is running but did not respond.',
            )
        if not start:
            loaded = systemctl('show', '-p', 'LoadState', '--value', user=True)
            can_start = loaded.stdout.strip() == 'loaded'
            message = (
                'Lemonade is offline.'
                if can_start
                else 'The Lemonade user service is unavailable.'
            )
            return dict(models=None, can_start=can_start, message=message)

        result = systemctl('start', '--no-block', user=True)
        if result.returncode:
            message = result.stderr.strip() or 'Could not start Lemonade.'
        else:
            # Type=simple reports started before the HTTP listener is ready.
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                time.sleep(0.4)
                try:
                    models = chat_models(port, keys)
                except (OSError, http.client.HTTPException):
                    continue
                return dict(models=models, can_start=False, message='')
            message = 'Lemonade did not respond after starting. Check its service logs.'
        return dict(models=None, can_start=True, message=message)
    except (
        OSError,
        ValueError,
        TypeError,
        KeyError,
        AttributeError,
        subprocess.TimeoutExpired,
    ) as error:
        message = str(error)
        can_start = False
    return dict(models=None, can_start=can_start, message=message)


def open_pi(path, model):
    port, keys = connection(system_service_active())
    env = dict(os.environ, **keys, LEMONADE_HOST=HOST, LEMONADE_PORT=str(port))
    command = ['lemonade', '--no-discovery', 'launch', 'pi']
    if model:
        command.append('--model=' + model)
    return subprocess.run(command, cwd=path, env=env, check=False).returncode
