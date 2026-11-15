"""Launch preferences persist by store identity and affect only game launches."""

import json
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock

import support

sys.path.insert(0, str(support.DESKTOP))
from spaces.games import backend, launch


class GamesSettingsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.env = {
            'HOME': str(self.home),
            'PATH': '',
            'PROTONPATH': '/inherited',
            'MANGOHUD': '1',
        }
        self.tools = {
            'legendary': '/bin/legendary',
            'umu-run': '/tools with spaces/umu-run',
            'mangohud': '/bin/mangohud',
        }
        self.worker = backend.GamesBackend(
            self.home / 'games.json', self.home / 'data', env=self.env
        )
        self.worker._which = self.tools.get
        self.worker._spawn_detached = Mock()
        self.game = self.worker._save_game(
            'settings',
            {
                'catalogProvider': 'fixture',
                'catalogProviderId': 'settings',
                'title': 'Example',
                'storeReferences': [
                    {'store': 'epic', 'externalId': 'Example'},
                    {'store': 'steam', 'externalId': '123'},
                ],
            },
        )
        self.worker._library_snapshot = {
            'epic': {
                'items': [
                    {'externalId': 'Example', 'installed': True, 'title': 'Example'}
                ]
            }
        }
        self.worker._library_updated = self.worker._clock()
        self.proton = self.home / 'Proton with spaces'
        self.proton.mkdir()
        executable = self.proton / 'proton'
        executable.write_text('#!/bin/sh\nexit 0\n')
        executable.chmod(0o700)

    def save(self, settings, game=False):
        return self.worker.handle(
            {
                'op': 'save_settings',
                'settings': settings,
                **({'gameId': self.game['id']} if game else {}),
            }
        )

    def launch(self):
        self.worker._launch_epic(self.game['id'], self.game, 'Example')
        return self.worker._spawn_detached.call_args

    def test_defaults_and_per_game_overrides_persist_and_apply_without_changing_prefix(
        self,
    ):
        self.save({'overlay': 'detailed', 'proton': str(self.proton)})
        first = self.launch()
        self.assertEqual(
            shlex.split(first.args[0][-2]), ['/bin/mangohud', self.tools['umu-run']]
        )
        self.assertEqual(first.kwargs['env']['PROTONPATH'], str(self.proton))
        self.assertIn('gpu_temp', first.kwargs['env']['MANGOHUD_CONFIG'])
        self.save({'overlay': 'off', 'proton': ''}, game=True)
        second = self.launch()
        self.assertEqual(shlex.split(second.args[0][-2]), [self.tools['umu-run']])
        self.assertEqual(second.kwargs['env']['MANGOHUD'], '0')
        self.assertNotIn('PROTONPATH', second.kwargs['env'])
        self.assertEqual(
            first.kwargs['env']['WINEPREFIX'], second.kwargs['env']['WINEPREFIX']
        )
        reopened = backend.GamesBackend(
            self.home / 'games.json', self.home / 'data', env=self.env
        )
        self.assertEqual(reopened._launch_settings()['proton'], str(self.proton))
        self.assertEqual(reopened._launch_settings('epic:Example')['overlay'], 'off')
        self.assertEqual(reopened._launch_settings('epic:Example')['proton'], '')
        self.save({'overlay': 'inherit', 'proton': 'inherit'}, game=True)
        self.assertEqual(self.launch().kwargs['env']['PROTONPATH'], str(self.proton))
        self.assertEqual(self.env['PROTONPATH'], '/inherited')

    def test_invalid_edits_leave_saved_settings_intact(self):
        self.save({'overlay': 'fps'})
        for settings in (
            {'proton': '/missing'},
            {'overlay': 'inherit'},
            {'overlay': 'fps', 'unknown': True},
            {'proton': None},
        ):
            with self.subTest(settings=settings), self.assertRaises(backend.GamesError):
                self.save(settings)
        self.tools.pop('mangohud')
        with self.assertRaisesRegex(backend.GamesError, 'MangoHud'):
            self.save({'overlay': 'detailed'})
        self.assertEqual(self.worker._launch_settings()['overlay'], 'fps')

    def test_missing_runner_is_reported_before_a_game_process_is_spawned(self):
        self.save({'proton': str(self.proton)})
        (self.proton / 'proton').unlink()
        with self.assertRaisesRegex(
            backend.GamesError, 'selected Proton is unavailable'
        ):
            self.launch()
        self.worker._spawn_detached.assert_not_called()

    def test_discovery_includes_other_steam_libraries_and_deduplicates_links(self):
        steam = self.home / 'Steam'
        custom = steam / 'compatibilitytools.d/GE-Proton'
        custom.parent.mkdir(parents=True)
        custom.symlink_to(self.proton, target_is_directory=True)
        extra = self.home / 'another library'
        runner = extra / 'steamapps/common/Proton Test'
        runner.mkdir(parents=True)
        (runner / 'proton').write_text('')
        (runner / 'proton').chmod(0o700)
        found = launch.runners(self.env, [steam], [extra], str(self.proton))
        self.assertEqual(found[0]['id'], '')
        self.assertEqual(
            {row['id'] for row in found[1:]}, {str(self.proton), str(runner)}
        )

    def test_per_game_choices_follow_epic_identity_and_do_not_leak_to_other_games(self):
        self.save({'overlay': 'fps'}, game=True)
        self.assertEqual(
            self.worker.game_settings({'gameId': self.game['id']})['stores'][0][
                'settings'
            ]['overlay'],
            'fps',
        )
        other = self.worker._save_game(
            'another',
            {
                'catalogProvider': 'fixture',
                'catalogProviderId': 'another',
                'title': 'Another',
            },
        )
        with self.assertRaises(backend.GamesError):
            self.worker.save_settings(
                {'gameId': other['id'], 'settings': {'overlay': 'off'}}
            )
        self.assertEqual(
            self.worker._launch_settings('epic:Another')['overlay'], 'inherit'
        )

    def test_native_and_flatpak_protonplus_handoffs_use_argument_lists(self):
        self.tools['flatpak'] = '/bin/flatpak'
        self.worker._runner = Mock(return_value=subprocess.CompletedProcess([], 0))
        result = self.worker.settings_action({'action': 'protonplus'})
        self.assertTrue(result['handoff'])
        self.assertEqual(
            self.worker._spawn_detached.call_args.args[0],
            ['/bin/flatpak', 'run', 'com.vysp3r.ProtonPlus'],
        )
        self.tools['protonplus'] = '/native/protonplus'
        self.worker.settings_action({'action': 'protonplus'})
        self.assertEqual(
            self.worker._spawn_detached.call_args.args[0], ['/native/protonplus']
        )

    def test_folder_handoff_rechecks_the_install_directory(self):
        install = self.home / 'installed game'
        install.mkdir()
        self.worker._library_snapshot['epic']['items'][0]['installPath'] = str(install)
        self.tools['xdg-open'] = '/bin/xdg-open'
        self.worker.settings_action(
            {'action': 'folder', 'gameId': self.game['id'], 'store': 'epic'}
        )
        self.assertEqual(
            self.worker._spawn_detached.call_args.args[0],
            ['/bin/xdg-open', install.as_uri()],
        )
        install.rmdir()
        with self.assertRaisesRegex(backend.GamesError, 'folder is unavailable'):
            self.worker.settings_action(
                {'action': 'folder', 'gameId': self.game['id'], 'store': 'epic'}
            )

    def test_private_configured_runner_remains_the_initial_default(self):
        config = self.home / 'games.json'
        config.write_text(json.dumps({'proton_path': str(self.proton)}))
        config.chmod(0o600)
        self.assertEqual(self.worker._launch_settings()['proton'], str(self.proton))
        self.save({'overlay': 'fps'})
        config.write_text('{}')
        self.assertEqual(self.worker._launch_settings()['proton'], '')
        self.save({'proton': ''})
        config.write_text(json.dumps({'proton_path': str(self.proton)}))
        self.assertEqual(self.worker._launch_settings()['proton'], '')

    def test_performance_overrides_cover_each_store_and_reset_to_current_defaults(self):
        self.worker._library_snapshot['steam'] = {
            'items': [{'externalId': '123', 'title': 'Example', 'installed': True}]
        }
        self.save(
            {
                'overlay': 'fps',
                'fpsLimit': 60,
                'position': 'bottom-right',
                'size': 'large',
            }
        )
        self.worker.save_settings(
            {
                'gameId': self.game['id'],
                'store': 'steam',
                'settings': {'fpsLimit': 30, 'overlay': 'off'},
            }
        )
        effective = self.worker._effective_launch('steam', '123')
        self.assertEqual(
            (effective['fpsLimit'], effective['overlay'], effective['position']),
            (30, 'off', 'bottom-right'),
        )
        self.worker.set_preferred_store({'gameId': self.game['id'], 'store': 'steam'})
        self.assertEqual(
            self.worker.availability({'gameId': self.game['id']})['preferredStore'],
            'steam',
        )
        result = self.worker.reset_game_settings({'gameId': self.game['id']})
        self.assertEqual(result['preferredStore'], '')
        self.assertEqual(self.worker._effective_launch('steam', '123')['fpsLimit'], 60)
        self.assertTrue(
            all(
                all(value == 'inherit' for value in store['settings'].values())
                for store in result['stores']
            )
        )
        for value in (-1, 1001, True, 30.5, '60'):
            with self.subTest(value=value), self.assertRaises(backend.GamesError):
                self.save({'fpsLimit': value})


if __name__ == '__main__':
    unittest.main()
