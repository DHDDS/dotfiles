"""Read itch's cached purchases and installations without reading authentication keys."""

import os
from pathlib import Path
import re
import sqlite3
import subprocess
import urllib.parse

from spaces.games import store_metadata

MAX_ROWS = 20000


def game_id(value):
    text = str(value or '').strip()
    return text if re.fullmatch(r'[1-9][0-9]{0,18}', text) else ''


def store_url(value):
    if not isinstance(value, str) or len(value) > 2048:
        return ''
    try:
        parsed = urllib.parse.urlsplit(value)
        if (
            parsed.scheme == 'https'
            and re.fullmatch(
                r'[a-zA-Z0-9][a-zA-Z0-9-]*\.itch\.io', parsed.hostname or ''
            )
            and re.fullmatch(r'/[a-zA-Z0-9][a-zA-Z0-9_-]*/?', parsed.path)
            and not parsed.username
            and not parsed.password
            and parsed.port in (None, 443)
            and not parsed.query
            and not parsed.fragment
        ):
            return f'https://{parsed.hostname}{parsed.path.rstrip("/")}'
    except ValueError:
        pass
    return ''


def command(env, which):
    home = Path(env.get('HOME', str(Path.home())))
    setup = home / '.itch/itch-setup'
    if setup.is_file() and os.access(setup, os.X_OK):
        return [str(setup), '--appname', 'itch', '--prefer-launch']
    if executable := which('itch'):
        return [executable]
    if executable := which('itch-setup'):
        return [executable, '--appname', 'itch', '--prefer-launch']
    return []


def direct_command(env, which, runner):
    launcher = command(env, which)
    if not launcher:
        return []
    if Path(launcher[0]).name != 'itch-setup':
        return []
    try:
        result = runner(
            [launcher[0], '--help'],
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
            timeout=5,
            check=False,
            env=env,
        )
        if '--run-game' in (result.stdout or '') + (result.stderr or ''):
            return [launcher[0], '--appname', 'itch', '--run-game']
    except (OSError, subprocess.SubprocessError):
        pass
    return []


def _owned(path):
    db = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=0.5)
    try:
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA query_only=ON')
        tables = {
            row[0]
            for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")
        }
        if not {'profiles', 'download_keys', 'games'}.issubset(tables):
            return [], False
        columns = {row['name'] for row in db.execute('PRAGMA table_info(profiles)')}
        if not {'id', 'user_id'}.issubset(columns):
            return [], False
        # Only identifiers are selected from profiles; api_key is never read.
        profiles = db.execute('SELECT id,user_id FROM profiles LIMIT 2').fetchall()
        if len(profiles) != 1:
            return [], False
        owners = (profiles[0]['id'], profiles[0]['user_id'])
        owned_query = 'SELECT game_id FROM download_keys WHERE owner_id IN (?,?)'
        args = list(owners)
        if {'bundle_keys', 'bundle_games'}.issubset(tables):
            owned_query += (
                ' UNION SELECT bg.game_id FROM bundle_games bg JOIN bundle_keys bk '
                'ON bk.bundle_id=bg.bundle_id WHERE bk.owner_id IN (?,?)'
            )
            args += owners
        fields = {row['name'] for row in db.execute('PRAGMA table_info(games)')}
        optional = ','.join(
            f'g.{key}' if key in fields else f"'' AS {key}"
            for key in (
                'url',
                'short_text',
                'cover_url',
                'still_cover_url',
                'classification',
            )
        )
        rows = db.execute(
            f'SELECT g.id,g.title,{optional} FROM games g WHERE g.id IN ({owned_query}) LIMIT ?',
            (*args, MAX_ROWS + 1),
        ).fetchall()
        if len(rows) > MAX_ROWS:
            raise ValueError('itch library is too large')
    finally:
        db.close()
    items = []
    for row in rows:
        identifier = game_id(row['id'])
        title = store_metadata.plain_text(row['title'])[:180]
        if (
            not identifier
            or not title
            or row['classification'] not in ('', None, 'game')
        ):
            continue
        url = store_url(row['url'])
        items.append(
            {
                'store': 'itch',
                'externalId': identifier,
                'title': title,
                'installed': False,
                'launchable': False,
                'storeUrl': url,
                'slug': url,
                'metadata': {
                    'summary': store_metadata.plain_text(row['short_text']),
                    'cover': store_metadata.image(
                        row['still_cover_url'] or row['cover_url']
                    ),
                    'officialWebsite': url,
                },
            }
        )
    return items, True


def _installed(path, launcher):
    # mode=ro observes SQLite WAL updates; immutable=1 would miss a running app's
    # recent installs. Select only game/install fields, never profiles or tokens.
    db = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=0.5)
    try:
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA query_only=ON')
        budget = 2000

        def bounded():
            nonlocal budget
            budget -= 1
            return budget <= 0

        db.set_progress_handler(bounded, 1000)
        game_columns = {row['name'] for row in db.execute('PRAGMA table_info(games)')}
        cave_columns = {row['name'] for row in db.execute('PRAGMA table_info(caves)')}
        if not {'id', 'title'}.issubset(game_columns) or not {
            'game_id',
            'install_location_id',
            'install_folder_name',
        }.issubset(cave_columns):
            raise ValueError('Unsupported itch database')
        optional = ', '.join(
            f'g.{name}' if name in game_columns else f"'' AS {name}"
            for name in (
                'url',
                'short_text',
                'cover_url',
                'still_cover_url',
                'classification',
            )
        )
        custom = (
            'c.custom_install_folder'
            if 'custom_install_folder' in cave_columns
            else "''"
        )
        rows = db.execute(
            f'SELECT g.id, g.title, {optional}, {custom} AS custom_folder, '
            'c.install_folder_name, l.path AS location '
            'FROM caves c JOIN games g ON g.id=c.game_id '
            'LEFT JOIN install_locations l ON l.id=c.install_location_id '
            'ORDER BY g.id LIMIT ?',
            (MAX_ROWS + 1,),
        ).fetchall()
        if len(rows) > MAX_ROWS:
            raise ValueError('itch library is too large')
    finally:
        db.close()
    items = {}
    for row in rows:
        identifier = game_id(row['id'])
        title = store_metadata.plain_text(row['title'])[:180]
        if (
            not identifier
            or not title
            or row['classification'] not in ('', None, 'game')
        ):
            continue
        try:
            if row['custom_folder']:
                install = Path(row['custom_folder'])
            else:
                location = Path(row['location'] or '')
                folder = Path(row['install_folder_name'] or '')
                if (
                    not location.is_absolute()
                    or folder.is_absolute()
                    or '..' in folder.parts
                    or not folder.parts
                ):
                    continue
                install = location / folder
            if not install.is_absolute() or not install.is_dir():
                continue
        except (OSError, ValueError, TypeError):
            continue
        url = store_url(row['url'])
        items[identifier] = {
            'store': 'itch',
            'externalId': identifier,
            'title': title,
            'installed': True,
            'launchable': bool(launcher),
            'installPath': str(install),
            'storeUrl': url,
            'slug': url,
            'metadata': {
                'summary': store_metadata.plain_text(row['short_text']),
                'cover': store_metadata.image(
                    row['still_cover_url'] or row['cover_url']
                ),
                'officialWebsite': url,
            },
        }
    return list(items.values())


def read(env, which):
    home = Path(env.get('HOME', str(Path.home())))
    path = Path(env.get('XDG_CONFIG_HOME', home / '.config')) / 'itch/db/butler.db'
    launcher = command(env, which)
    known, items, owned, ownership_cached = False, [], [], False
    try:
        if path.is_file():
            items = _installed(path, launcher)
            owned, ownership_cached = _owned(path)
            merged = {item['externalId']: item for item in owned}
            merged.update({item['externalId']: item for item in items})
            items = list(merged.values())
            known = True
            message = ''
        else:
            message = 'Open itch and refresh its library, then refresh Games.'
    except (OSError, ValueError, sqlite3.Error):
        message = (
            "itch's installed games could not be read. Open itch, then refresh Games."
        )
    if not launcher:
        message = 'Install the itch desktop app to launch and manage itch.io games.'
    return {
        'available': bool(launcher),
        'command': launcher,
        'ownershipKnown': False,
        # Positive cached purchases are known; absence from a partial cache is
        # never proof of non-ownership.
        'ownedIds': [item['externalId'] for item in owned],
        'ownershipCached': ownership_cached,
        'installationKnown': known,
        'items': items,
        'message': message,
    }
