# Pi

The module installs Pi through AUR and uses npm for its user packages.
The apply hook installs `pi-web-access` and `pi-lens` through Pi's native
package manager as the desktop user. Pi writes the package entries into
its existing `settings.json` in `$PI_CODING_AGENT_DIR`.

The [Topgrade module](../../system/package/topgrade/ARCHITECTURE.md) updates
these unpinned packages through its **Pi extensions** command.
