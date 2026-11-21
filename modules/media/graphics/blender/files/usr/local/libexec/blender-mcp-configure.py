"""Configure the Blender Lab MCP extension through Blender's Python API."""

import os
import sys
from pathlib import Path

import bpy

REPOSITORY = 'lab_blender_org'
ADDON = f'bl_ext.{REPOSITORY}.mcp'
REMOTE = 'https://lab.blender.org/'
HOST = 'localhost'
PORT = 9876
MANIFEST = Path('mcp/blender_manifest.toml')


def require_finished(result, action):
    if result != {'FINISHED'}:
        raise RuntimeError(f'{action} failed: {result}')


def configure(*, install):
    if not install:
        config_file = Path(bpy.utils.user_resource('CONFIG')) / 'userpref.blend'
        if not config_file.exists() and bpy.ops.preferences.copy_prev.poll():
            require_finished(
                bpy.ops.preferences.copy_prev(),
                'Importing previous Blender preferences',
            )
            print('Blender MCP: imported the previous version’s preferences')

    preferences = bpy.context.preferences
    data_home = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
    shared_repository = data_home / 'blender/extensions' / REPOSITORY
    repository = next(
        (repo for repo in preferences.extensions.repos if repo.module == REPOSITORY),
        None,
    )
    addon = preferences.addons.get(ADDON)
    mcp = addon.preferences if addon is not None else None
    if (
        repository is not None
        and repository.enabled
        and repository.use_remote_url
        and repository.remote_url == REMOTE
        and (Path(repository.directory) / MANIFEST).is_file()
        and preferences.system.use_online_access
        and mcp is not None
        and (mcp.host, mcp.port, mcp.use_autostart) == (HOST, PORT, True)
    ):
        print('Blender MCP: Auto Start is configured')
        return

    # Keep populated repositories and custom paths selected by the user.
    directory = Path(repository.directory) if repository is not None else None
    use_shared = repository is None or (
        not repository.use_custom_directory
        and not any(directory.glob('*/blender_manifest.toml'))
    )
    if use_shared:
        directory = shared_repository
    if not install and not (directory / MANIFEST).is_file():
        raise RuntimeError(
            'The Blender Lab MCP add-on is missing. Run blender-mcp-setup --install.'
        )

    # The bridge checks this permission even for its localhost socket.
    preferences.system.use_online_access = True
    if repository is None:
        repository = preferences.extensions.repos.new(
            name='Blender Lab',
            module=REPOSITORY,
            remote_url=REMOTE,
            custom_directory=str(directory),
        )
    elif use_shared:
        repository.custom_directory = str(directory)
        repository.use_custom_directory = True
    repository.enabled = True
    repository.use_remote_url = True
    repository.remote_url = REMOTE

    if not (directory / MANIFEST).is_file():
        require_finished(
            bpy.ops.extensions.repo_sync(repo_directory=repository.directory),
            'Blender Lab repository sync',
        )
        require_finished(
            bpy.ops.extensions.package_install(
                repo_directory=repository.directory,
                pkg_id='mcp',
                enable_on_install=True,
            ),
            'MCP extension installation',
        )
    addon = preferences.addons.get(ADDON)
    if addon is None or addon.preferences is None:
        require_finished(bpy.ops.preferences.addon_enable(module=ADDON), 'MCP enable')

    mcp = preferences.addons[ADDON].preferences
    if mcp is None:
        raise RuntimeError('MCP add-on preferences are unavailable after enabling it')
    mcp.host = HOST
    mcp.port = PORT
    mcp.use_autostart = True
    require_finished(bpy.ops.wm.save_userpref(), 'Saving Blender preferences')
    print('Blender MCP: online access and Auto Start enabled on localhost:9876')


if __name__ == '__main__':
    configure(install=sys.argv[-1] == '--install')
