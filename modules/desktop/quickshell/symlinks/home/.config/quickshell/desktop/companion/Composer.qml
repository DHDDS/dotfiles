import QtQuick
import QtQuick.Layouts
import "../ui"

// A one-line message box. Enter sends; Escape and clicking elsewhere close it.
Surface {
    id: root

    property string placeholder: qsTr("Type a message…")

    signal submitted(string text)
    signal dismissed

    function focusInput(): void {
        field.forceActiveFocus();
    }

    color: Theme.background
    implicitHeight: row.implicitHeight + 2 * Theme.spacingSmall

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Theme.spacingSmall
        spacing: Theme.spacingSmall
        PlainInputField {
            id: field
            objectName: "companionInput"
            Layout.fillWidth: true
            placeholderText: root.placeholder
            Keys.onEscapePressed: root.dismissed()
            onAccepted: send()
            function send(): void {
                if (text.trim()) {
                    root.submitted(text.trim());
                    text = "";
                }
            }
        }
        ShellButton {
            text: qsTr("Send")
            enabled: field.text.trim() !== ""
            onClicked: field.send()
        }
    }
}
