"""itch's local SQLite library and launcher handoffs, without credentials."""

from contextlib import closing
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

import support

sys.path.insert(0, str(support.DESKTOP))
from spaces.games import backend, igdb, itch


class ItchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.env = {
            'HOME': str(self.home),
            'XDG_CONFIG_HOME': str(self.home / 'config'),
            'PATH': '',
        }
        self.path = self.home / 'config/itch/db/butler.db'
        self.path.parent.mkdir(parents=True)
        self.install = self.home / 'games/Example'
        self.install.mkdir(parents=True)
        with closing(sqlite3.connect(self.path)) as db, db:
            db.executescript("""
                CREATE TABLE games(id INTEGER PRIMARY KEY, title TEXT, url TEXT,
                    short_text TEXT, cover_url TEXT, still_cover_url TEXT, classification TEXT);
                CREATE TABLE caves(id TEXT, game_id INTEGER, install_location_id TEXT,
                    install_folder_name TEXT, custom_install_folder TEXT);
                CREATE TABLE install_locations(id TEXT, path TEXT);
                CREATE TABLE profiles(id INTEGER, user_id INTEGER, api_key TEXT);
                INSERT INTO profiles VALUES(17,17,'never-read-this');
                CREATE TABLE download_keys(id INTEGER,game_id INTEGER,owner_id INTEGER);
                CREATE TABLE bundle_keys(id INTEGER,bundle_id INTEGER,owner_id INTEGER);
                CREATE TABLE bundle_games(bundle_id INTEGER,game_id INTEGER);
            """)
            db.execute(
                'INSERT INTO install_locations VALUES(?,?)',
                ('location', str(self.install.parent)),
            )
            db.execute(
                'INSERT INTO games VALUES(?,?,?,?,?,?,?)',
                (
                    123,
                    'Example',
                    'https://creator.itch.io/example',
                    '<p>Short description</p>',
                    'https://img.itch.zone/cover.png',
                    '',
                    'game',
                ),
            )
            db.execute(
                'INSERT INTO caves VALUES(?,?,?,?,?)',
                ('cave', 123, 'location', 'Example', ''),
            )
            # Viewed games are cached too; they must never appear as owned.
            db.execute(
                'INSERT INTO games VALUES(?,?,?,?,?,?,?)',
                (456, 'Only viewed', '', '', '', '', 'game'),
            )
        self.tools = {'itch': '/bin/itch'}

    def read(self):
        return itch.read(self.env, self.tools.get)

    def worker(self):
        worker = backend.GamesBackend(
            self.home / 'games.json', self.home / 'data', env=self.env
        )
        worker._which = self.tools.get
        worker._spawn_detached = Mock()
        worker._request = Mock(side_effect=AssertionError('No network reads'))
        worker._library_snapshot = {'itch': self.read()}
        worker._library_updated = worker._clock()
        return worker

    def test_installed_games_have_metadata_without_claiming_ownership_or_changing_db(
        self,
    ):
        original = self.path.read_bytes()
        state = self.read()
        self.assertTrue(state['available'] and state['installationKnown'])
        self.assertFalse(state['ownershipKnown'])
        self.assertEqual(state['ownedIds'], [])
        self.assertEqual([item['externalId'] for item in state['items']], ['123'])
        item = state['items'][0]
        self.assertEqual(item['metadata']['summary'], 'Short description')
        self.assertEqual(
            item['metadata']['cover']['url'], 'https://img.itch.zone/cover.png'
        )
        self.assertTrue(item['installed'] and item['launchable'])
        self.assertEqual(self.path.read_bytes(), original)

    def test_wal_changes_are_visible_and_a_missing_install_is_not_launchable(self):
        db = sqlite3.connect(self.path)
        self.addCleanup(db.close)
        db.execute('PRAGMA journal_mode=WAL')
        db.execute("UPDATE games SET title='Updated in WAL' WHERE id=123")
        db.commit()
        self.assertEqual(self.read()['items'][0]['title'], 'Updated in WAL')
        self.install.rmdir()
        self.assertEqual(self.read()['items'], [])

    def test_missing_or_corrupt_database_never_creates_a_library(self):
        self.path.unlink()
        self.assertFalse(self.read()['installationKnown'])
        self.assertFalse(self.path.exists())
        self.path.write_text('broken')
        state = self.read()
        self.assertFalse(state['installationKnown'])
        self.assertEqual(state['items'], [])
        self.assertIn('could not be read', state['message'])

    def test_cached_install_stays_visible_without_a_launcher(self):
        self.tools.clear()
        state = self.read()
        self.assertFalse(state['available'])
        self.assertTrue(state['items'][0]['installed'])
        self.assertFalse(state['items'][0]['launchable'])

    def test_cached_owned_and_bundle_games_are_listed_without_reading_api_keys(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute('INSERT INTO download_keys VALUES(1,456,17)')
            db.execute(
                'INSERT INTO games VALUES(?,?,?,?,?,?,?)',
                (
                    789,
                    'Bundle game',
                    'https://creator.itch.io/bundle-game',
                    '',
                    '',
                    '',
                    'game',
                ),
            )
            db.execute('INSERT INTO bundle_keys VALUES(1,55,17)')
            db.execute('INSERT INTO bundle_games VALUES(55,789)')
        connect = sqlite3.connect

        def guarded(*args, **kwargs):
            connection = connect(*args, **kwargs)
            connection.set_authorizer(
                lambda op, table, column, *_: (
                    sqlite3.SQLITE_DENY
                    if op == sqlite3.SQLITE_READ
                    and table == 'profiles'
                    and column == 'api_key'
                    else sqlite3.SQLITE_OK
                )
            )
            return connection

        with patch.object(itch.sqlite3, 'connect', side_effect=guarded):
            state = self.read()
        self.assertEqual(set(state['ownedIds']), {'456', '789'})
        self.assertTrue(state['ownershipCached'])
        self.assertFalse(state['ownershipKnown'])
        self.assertEqual(len(state['items']), 3)
        self.assertNotIn('never-read-this', str(state))
        worker = self.worker()
        owned = worker.library_games({'mode': 'owned'})['items']
        self.assertEqual(
            {game['title'] for game in owned}, {'Only viewed', 'Bundle game'}
        )
        game = next(game for game in owned if game['title'] == 'Bundle game')
        row = worker.availability({'gameId': game['id']})['stores'][-1]
        self.assertEqual(row['primaryAction']['type'], 'install')
        worker.action({'gameId': game['id'], 'actionId': row['primaryAction']['id']})
        self.assertEqual(
            worker._spawn_detached.call_args.args[0],
            ['/bin/itch', 'itch://install?game_id=789'],
        )

    def test_owned_cache_is_scoped_to_the_local_account_and_unknown_games_stay_unknown(
        self,
    ):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute('INSERT INTO download_keys VALUES(1,456,99)')
        self.assertEqual(self.read()['ownedIds'], [])
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute('INSERT INTO profiles VALUES(99,99,?)', ('another-secret',))
        self.assertFalse(self.read()['ownershipCached'])
        self.assertEqual(self.read()['ownedIds'], [])

    def test_direct_itch_launch_uses_the_shared_performance_preferences(self):
        setup = self.home / '.itch/itch-setup'
        setup.parent.mkdir()
        setup.write_text('#!/bin/sh\n')
        setup.chmod(0o700)
        worker = self.worker()
        worker._runner = Mock(
            return_value=subprocess.CompletedProcess([], 0, '--run-game', '')
        )
        self.tools['mangohud'] = '/bin/mangohud'
        worker.save_settings({'settings': {'overlay': 'off', 'fpsLimit': 40}})
        game = worker.library_games({'mode': 'installed'})['items'][0]
        result = worker.action({'gameId': game['id'], 'actionId': 'itch:play:123'})
        self.assertTrue(result['started'])
        args = worker._spawn_detached.call_args.args[0]
        self.assertEqual(
            args,
            ['/bin/mangohud', str(setup), '--appname', 'itch', '--run-game', '123'],
        )
        self.assertIn(
            'no_display',
            worker._spawn_detached.call_args.kwargs['env']['MANGOHUD_CONFIG'],
        )
        self.assertIn(
            'fps_limit=40',
            worker._spawn_detached.call_args.kwargs['env']['MANGOHUD_CONFIG'],
        )

    def test_custom_folders_and_non_game_classification(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute(
                'UPDATE caves SET custom_install_folder=?, install_location_id=?',
                (str(self.install), 'missing'),
            )
        self.assertEqual(self.read()['items'][0]['installPath'], str(self.install))
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("UPDATE games SET classification='tool'")
        self.assertEqual(self.read()['items'], [])

    def test_unsafe_folder_names_and_store_urls_are_rejected(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("UPDATE caves SET install_folder_name='../games/Example'")
        self.assertEqual(self.read()['items'], [])
        for url in (
            'https://itch.io.evil/example',
            'https://creator.itch.io/example?download_key=secret',
            'https://creator.itch.io:444/example',
            'http://creator.itch.io/example',
            'https://user@creator.itch.io/example',
        ):
            self.assertEqual(itch.store_url(url), '')

    def test_igdb_url_matches_local_numeric_identity_and_bad_ids_do_not_fall_back(self):
        game = igdb.normalize(
            {
                'id': 99,
                'name': 'Example',
                'websites': [{'url': 'https://creator.itch.io/example/'}],
            }
        )
        self.assertEqual(game['storeReferences'][0]['store'], 'itch')
        match, source = backend.match_library_item(game, 'itch', self.read()['items'])
        self.assertEqual(match['externalId'], '123')
        self.assertEqual(source, 'store-id')
        game['storeReferences'] = [{'store': 'itch', 'externalId': '999'}]
        self.assertIsNone(
            backend.match_library_item(game, 'itch', self.read()['items'])[0]
        )

    def test_library_listing_and_play_use_itch_without_directly_executing_payloads(
        self,
    ):
        worker = self.worker()
        game = worker.library_games({'mode': 'installed'})['items'][0]
        self.assertEqual(game['installedBy'], ['itch'])
        self.assertEqual(game['summary'], 'Short description')
        row = worker.availability({'gameId': game['id']})['stores'][-1]
        self.assertEqual(row['primaryAction']['type'], 'play')
        self.assertNotIn('uninstall', [action['type'] for action in row['actions']])
        result = worker.action({'gameId': game['id'], 'actionId': 'itch:play:123'})
        self.assertTrue(result['handoff'])
        self.assertEqual(
            worker._spawn_detached.call_args.args[0],
            ['/bin/itch', 'itch://install?game_id=123&launch'],
        )
        worker.action({'gameId': game['id'], 'actionId': 'itch:manage'})
        self.assertEqual(
            worker._spawn_detached.call_args.args[0][-1], 'itch://library/installed'
        )
        self.install.rmdir()
        with self.assertRaisesRegex(backend.GamesError, 'no longer reports'):
            worker.action({'gameId': game['id'], 'actionId': 'itch:play:123'})

    def test_updater_launcher_is_preferred_and_manual_url_matches_survive_refresh(self):
        setup = self.home / '.itch/itch-setup'
        setup.parent.mkdir()
        setup.write_text('#!/bin/sh\n')
        setup.chmod(0o700)
        self.assertEqual(
            self.read()['command'], [str(setup), '--appname', 'itch', '--prefer-launch']
        )
        worker = self.worker()
        game = worker._save_game(
            'manual',
            {
                'catalogProvider': 'fixture',
                'catalogProviderId': 'manual',
                'title': 'Different title',
            },
        )
        worker._save_store_match(game['id'], 'itch', 'https://creator.itch.io/example/')
        row = worker.availability({'gameId': game['id']})['stores'][-1]
        self.assertTrue(row['launchable'])
        self.assertEqual(row['externalId'], '123')


if __name__ == '__main__':
    unittest.main()
