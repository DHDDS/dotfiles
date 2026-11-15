"""The generated asset inventory must contain every Space's QML dependencies."""

import json
import unittest

import support


def use_generated_space_assets(root):
    config = json.loads((support.REPO / 'user-configuration.json').read_text())
    prefix = 'home/.config/quickshell/desktop/'
    installed = {
        item['target'][len(prefix):]
        for kind in ('files', 'symlinks')
        for item in config.get('extra', {}).get(kind, [])
        if item['target'].startswith(prefix)
    }
    if not any(path.startswith('spaces/') for path in installed):
        raise AssertionError('The generated configuration does not include Spaces')
    for path in (root / 'spaces').rglob('*.qml'):
        if path.relative_to(root).as_posix() not in installed:
            path.unlink()


@unittest.skipUnless(support.QS, 'Quickshell is required')
class SpacesInventoryTests(unittest.TestCase):
    def test_generated_assets_load_every_registered_space(self):
        support.run_qml(
            self,
            """import QtQuick
import Quickshell
import "ui"
ShellRoot {
 Timer {
  interval: 20; running: true
  onTriggered: {
   const sharedCard = Qt.createComponent(Qt.resolvedUrl("ui/SpaceResultCard.qml"));
   if (sharedCard.status !== Component.Ready) {
    console.error("DISPLAY_FAIL", "shared launcher card", sharedCard.errorString());
    Qt.quit();
    return;
   }
   for (const entry of SpaceState.entries) {
    const component = Qt.createComponent(Qt.resolvedUrl("ui/" + entry.source));
    if (component.status !== Component.Ready) {
     console.error("DISPLAY_FAIL", entry.id, component.errorString());
     Qt.quit();
     return;
    }
   }
   console.log("DISPLAY_PASS");
   Qt.quit();
  }
 }
}""",
            setup=use_generated_space_assets,
        )
