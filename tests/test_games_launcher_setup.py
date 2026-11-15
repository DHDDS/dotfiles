"""Launcher edits preserve user configuration; performance wrappers run the game."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import support

sys.path.insert(0, str(support.DESKTOP))
from spaces.games import backend, launch, launcher_setup


class LauncherSetupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.env = {
            **os.environ,
            'HOME': str(self.home),
            'XDG_DATA_HOME': str(self.home / 'data'),
            'STEAM_USE_MANGOAPP': '0',
        }
        self.worker = backend.GamesBackend(
            self.home / 'config/games.json',
            self.home / 'data/quickshell/desktop/spaces/games',
            env=self.env,
        )

    def test_steam_edits_only_launch_options_and_is_idempotent(self):
        text = """// Keep this comment and spacing.
"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" {
"123" { "LaunchOptions" "PROTON_LOG=1 gamemoderun %command% -safe" "Other" "unchanged" }
"456" { "Favorite" "1" }
} "Unrelated" "value" } } } }
"""
        wrapper = self.home / 'path with spaces/launch.py'
        changed, count = launcher_setup.steam_options(
            text, ['123', '456', '789'], wrapper
        )
        self.assertEqual(count, 3)
        self.assertIn('// Keep this comment and spacing.', changed)
        self.assertIn('"Other" "unchanged"', changed)
        self.assertIn('"Unrelated" "value"', changed)
        apps = backend.parse_vdf(changed)['UserLocalConfigStore']['Software']['Valve'][
            'Steam'
        ]['apps']
        option = apps['123']['LaunchOptions']
        self.assertTrue(option.startswith('PROTON_LOG=1 gamemoderun '))
        self.assertTrue(option.endswith('%command% -safe'))
        self.assertIn(str(wrapper), shlex.split(option))
        self.assertEqual(apps['456']['Favorite'], '1')
        self.assertIn('steam 789 -- %command%', apps['789']['LaunchOptions'])
        repeated, count = launcher_setup.steam_options(
            changed, ['123', '456', '789'], wrapper
        )
        self.assertEqual((repeated, count), (changed, 0))

    def test_missing_steam_nodes_are_created_without_erasing_other_values(self):
        original = '"UserLocalConfigStore" { "Keep" "yes" }'
        updated, _ = launcher_setup.steam_options(
            original, ['123'], self.home / 'launch.py'
        )
        data = backend.parse_vdf(updated)['UserLocalConfigStore']
        self.assertEqual(data['Keep'], 'yes')
        self.assertIn(
            '%command%',
            data['Software']['Valve']['Steam']['apps']['123']['LaunchOptions'],
        )
        for original in ('"root" { "same" "a" "same" "b" }', '"broken" {'):
            with self.assertRaises(ValueError):
                launcher_setup.steam_options(original, ['123'], self.home / 'launch.py')

    def test_embedded_steam_commands_and_concurrent_changes_are_not_overwritten(self):
        value = json.dumps('bash -c "%command%"')
        text = (
            '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "123" { "LaunchOptions" '
            + value
            + ' } } } } } }'
        )
        with self.assertRaisesRegex(ValueError, 'manual review'):
            launcher_setup.steam_options(text, ['123'], self.home / 'launch.py')
        path = self.home / 'changed.vdf'
        path.write_text('new client content')
        with self.assertRaisesRegex(ValueError, 'launcher changed'):
            launcher_setup.atomic_write(path, 'our change', original='old content')
        self.assertEqual(path.read_text(), 'new client content')

    def test_steam_wrapper_preserves_the_existing_gamescope_mangoapp_session(self):
        command = [
            sys.executable,
            str(support.DESKTOP / 'spaces/games/launch.py'),
            'steam',
            '123',
            '--',
            sys.executable,
            '-c',
            'import os;print(os.environ["MANGOHUD_CONFIG"])',
        ]
        env = dict(
            self.env, STEAM_USE_MANGOAPP='1', MANGOHUD_CONFIG='existing-session-overlay'
        )
        result = subprocess.run(
            command, env=env, capture_output=True, text=True, check=True
        )
        self.assertEqual(result.stdout.strip(), 'existing-session-overlay')

    def test_steam_setup_requires_a_stopped_client_and_preserves_the_file_on_refusal(
        self,
    ):
        steam = self.home / 'Steam'
        config = steam / 'userdata/1/config/localconfig.vdf'
        config.parent.mkdir(parents=True)
        original = '"UserLocalConfigStore" { "Keep" "yes" }'
        config.write_text(original)
        self.worker._steam_roots = lambda: [steam]
        self.worker._library_snapshot = {'steam': {'items': [{'externalId': '123'}]}}
        self.worker._library_updated = self.worker._clock()
        with patch.object(launcher_setup, 'running', return_value=True):
            with self.assertRaisesRegex(backend.GamesError, 'Quit Steam'):
                self.worker._setup_steam()
        self.assertEqual(config.read_text(), original)
        with patch.object(launcher_setup, 'running', return_value=False):
            result = self.worker._setup_steam()
        self.assertIn('1 Steam games', result['message'])
        self.assertTrue(self.worker._steam_ready('123'))
        self.assertFalse(self.worker._steam_ready('124'))

    def test_heroic_preserves_runner_cloud_and_custom_environment_fields(self):
        root = self.home / 'heroic'
        path = root / 'GamesConfig/123.json'
        path.parent.mkdir(parents=True)
        existing = {
            'version': 'v0.1',
            '123': {
                'winePrefix': '/saves/prefix',
                'wineVersion': {'name': 'Existing'},
                'autoSyncSaves': True,
                'enviromentOptions': [{'key': 'CUSTOM', 'value': 'keep me'}],
            },
        }
        path.write_text(json.dumps(existing))
        prefs = {**launch.PERFORMANCE_DEFAULTS, 'fpsLimit': 60}
        launcher_setup.heroic_performance(root, '123', prefs)
        current = json.loads(path.read_text())['123']
        for key in ('winePrefix', 'wineVersion', 'autoSyncSaves'):
            self.assertEqual(current[key], existing['123'][key])
        self.assertTrue(current['showMangohud'])
        env = {entry['key']: entry['value'] for entry in current['enviromentOptions']}
        self.assertEqual(env['CUSTOM'], 'keep me')
        self.assertEqual(env['MANGOHUD_CONFIG'], 'read_cfg')
        performance_file = Path(env['MANGOHUD_CONFIGFILE'])
        self.assertIn('no_display', performance_file.read_text())
        self.assertIn('fps_limit=60', performance_file.read_text())
        self.assertTrue(launcher_setup.heroic_managed(root, '123'))
        configured = path.read_text()
        launcher_setup.heroic_performance(
            root, '123', launch.PERFORMANCE_DEFAULTS, configure=False
        )
        self.assertEqual(path.read_text(), configured)
        self.assertIn('fps_limit=0', performance_file.read_text())
        self.assertTrue(json.loads(path.read_text())['123']['showMangohud'])
        path.write_text('{"version":"future"}')
        with self.assertRaises(ValueError):
            launcher_setup.heroic_performance(root, '123', prefs)
        self.assertEqual(path.read_text(), '{"version":"future"}')

    def test_heroic_refuses_initial_configuration_while_a_client_may_cache_old_settings(
        self,
    ):
        root = self.home / 'heroic'
        with self.assertRaisesRegex(ValueError, 'Quit Heroic'):
            launcher_setup.heroic_performance(
                root, '123', launch.PERFORMANCE_DEFAULTS, configure=False
            )
        self.assertFalse((root / 'GamesConfig/123.json').exists())

    def test_steam_wrapper_reads_saved_preferences_and_executes_a_real_fixture(self):
        self.worker._which = lambda name: (
            '/fixture/mangohud' if name == 'mangohud' else None
        )
        self.worker.save_settings(
            {
                'settings': {
                    'overlay': 'off',
                    'fpsLimit': 60,
                    'position': 'bottom-right',
                    'size': 'large',
                }
            }
        )
        commands = self.home / 'bin'
        commands.mkdir()
        mango = commands / 'mangohud'
        mango.write_text('#!/bin/sh\nexec "$@"\n')
        mango.chmod(0o700)
        command = [
            sys.executable,
            str(support.DESKTOP / 'spaces/games/launch.py'),
            'steam',
            '123',
            '--',
            sys.executable,
            '-c',
            'import json,os,sys;print(json.dumps([os.environ["MANGOHUD_CONFIG"],sys.argv[1:]]))',
            'a path with spaces',
            'literal;argument',
        ]
        self.worker._which = lambda name: str(mango) if name == 'mangohud' else None
        # save_settings validates the installation, so the fixture supplies MangoHud.
        env = dict(self.env, PATH=str(commands))
        result = subprocess.run(
            command, env=env, capture_output=True, text=True, check=True
        )
        config, args = json.loads(result.stdout)
        self.assertIn('no_display', config)
        self.assertIn('position=bottom-right', config)
        self.assertIn('font_size=32', config)
        self.assertIn('fps_limit=60', config)
        self.assertEqual(args, ['a path with spaces', 'literal;argument'])


if __name__ == '__main__':
    unittest.main()
