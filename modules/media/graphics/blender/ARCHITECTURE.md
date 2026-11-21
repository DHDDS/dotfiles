# Blender module

The native `blender` package comes from Arch's extra repository. The upstream
Blender Lab MCP server is a `uv` tool installed from its `mcp/` subproject on
the repository's default branch. There is no PKGBUILD or pinned commit; Topgrade
upgrades the installed uv tool, and configuration apply runs
`uv tool install --upgrade` against the declared source.

`scripts/50_blender.sh` runs `blender-mcp-setup --install` as the regular user
with the real home and XDG paths. The launcher runs `blender-mcp-configure.py`
in background Blender.
The hook requires Blender to be closed so an open instance cannot overwrite the
saved preferences. `--disable-autoexec` disables blend-file Python execution;
`-noaudio` avoids starting an audio client during setup, and
`--python-exit-code 1` makes configuration errors fail the hook.

The helper registers and enables the `lab_blender_org` extension repository
(`https://lab.blender.org/`), installs its `mcp` extension if absent, and enables
the add-on. New or empty Blender Lab repositories store extensions under
`$XDG_DATA_HOME/blender/extensions/lab_blender_org`. New Blender versions
can reuse that directory after importing preferences or reapplying the module.
Populated repositories and existing custom paths retain their locations.
The helper preserves other preferences while setting Allow Online Access,
Auto Start, and the bridge address `localhost:9876`, then saves `userpref.blend`
through Blender. Online access is required by the add-on even for loopback.
Blender owns subsequent extension updates. Setup installs the extension only if
absent.

The Blender module's Topgrade post-command runs `blender-mcp-setup` as the
desktop user. With Blender closed, it imports the previous version's settings
through Blender's native operator when the current profile has no saved
preferences and Blender offers an import. It repairs MCP settings using the
locally installed extension and leaves healthy preferences untouched. If the
extension is missing, `blender-mcp-setup --install` can fetch it from Blender Lab.
Open Blender sessions defer the check until the user closes Blender and runs
the command.

When Codex is installed, the hook uses `codex mcp add` to configure a user-level
stdio entry named `blender`, launching `~/.local/bin/blender-mcp` on connection.
It uses `CODEX_HOME=~/.local/share/codex`, matching the Codex module. The ChatGPT
desktop app and local Codex clients share that configuration. The MCP process
runs on demand; the add-on's Auto Start preference starts the Blender-side bridge
when Blender opens.

Validate changes with background Blender in a disposable home: exercise a fresh
extension installation and repeated setup, check that unrelated preferences
survive, and read the saved preferences in a second process. After live setup,
open Blender and call an MCP scene-summary tool to verify the bridge.

Managed uv tool ownership/removal follows the shared
[package executor](../../../../scripts/ARCHITECTURE.md).
