import QtQuick
import QtQuick.Layouts
import "../ui"

// Shows exactly what a command or file change would do. Only a click decides;
// speech never approves anything.
Surface {
    id: root

    required property var activity
    readonly property var details: activity?.arguments ?? {}
    readonly property bool command: activity?.name === "run_command"

    signal decided(bool approved)

    color: Theme.background
    implicitHeight: column.implicitHeight + 2 * Theme.padding

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.spacingMedium

        ShellText {
            text: root.command ? qsTr("Run this command?") : qsTr("Write this file?")
            font.bold: true
        }
        ShellText {
            visible: !root.command
            text: root.details.path ?? ""
            color: Theme.muted
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(170, preview.implicitHeight + 16)
            color: Theme.surface
            radius: Theme.controlRadius
            Flickable {
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                contentWidth: preview.implicitWidth
                contentHeight: preview.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Text {
                    id: preview
                    text: (root.command ? root.details.command : root.details.content) ?? ""
                    textFormat: Text.PlainText
                    color: Theme.text
                    font.family: Theme.monospaceFamily
                    font.pixelSize: Theme.smallFontSize
                }
            }
        }
        ShellText {
            visible: root.command
            text: qsTr("Runs in %1 for up to %2 seconds.").arg(root.activity?.working_directory ?? "~").arg(root.activity?.timeout_seconds ?? 30)
            color: Theme.muted
            font.pixelSize: Theme.smallFontSize
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Theme.spacingSmall
            ShellButton {
                objectName: "approvalDeny"
                text: qsTr("Don't")
                onClicked: root.decided(false)
            }
            ShellButton {
                objectName: "approvalAllow"
                text: root.command ? qsTr("Run it") : qsTr("Write it")
                idleColor: Theme.accentSurface
                onClicked: root.decided(true)
            }
        }
    }
}
