pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../ui"
import "../drawers/assistant/Markdown.js" as Markdown

// The full answer when more was written than spoken. The Assistant's safe
// Markdown segments keep code as plain text and load no remote content.
Surface {
    id: root

    required property string text
    property bool canContinue: false

    signal closed
    signal continueRequested

    color: Theme.background
    implicitHeight: Math.min(330, layout.implicitHeight + 2 * Theme.padding)

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.spacingSmall

        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: content.implicitHeight
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: content
                width: scroller.width
                spacing: Theme.spacingSmall
                Repeater {
                    model: Markdown.segments(root.text)
                    Item {
                        id: segment
                        required property var modelData
                        Layout.fillWidth: true
                        readonly property bool code: modelData.kind === "code"
                        implicitHeight: segment.code ? codeBox.implicitHeight : prose.implicitHeight
                        Text {
                            id: prose
                            visible: !segment.code
                            width: parent.width
                            text: segment.code ? "" : segment.modelData.text
                            textFormat: Text.MarkdownText
                            wrapMode: Text.Wrap
                            color: Theme.text
                            linkColor: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            onLinkActivated: link => Apps.openUrl(link, "assistant")
                        }
                        Rectangle {
                            id: codeBox
                            visible: segment.code
                            width: parent.width
                            implicitHeight: codeText.implicitHeight + 12
                            color: Theme.surface
                            radius: Theme.controlRadius
                            Text {
                                id: codeText
                                x: 6
                                y: 6
                                width: parent.width - 12
                                text: segment.code ? segment.modelData.text : ""
                                wrapMode: Text.WrapAnywhere
                                color: Theme.text
                                font.family: Theme.monospaceFamily
                                font.pixelSize: Theme.smallFontSize
                            }
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Theme.spacingSmall
            ShellButton {
                objectName: "continueInAssistant"
                visible: root.canContinue
                text: qsTr("Continue in Assistant")
                onClicked: root.continueRequested()
            }
            ShellButton {
                text: qsTr("Copy")
                onClicked: Quickshell.clipboardText = root.text
            }
            ShellButton {
                objectName: "detailsClose"
                text: qsTr("Close")
                onClicked: root.closed()
            }
        }
    }
}
