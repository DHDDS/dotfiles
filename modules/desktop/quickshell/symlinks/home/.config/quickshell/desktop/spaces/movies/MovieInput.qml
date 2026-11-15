import QtQuick
import QtQuick.Controls

TextField {
    id: root

    property bool clearable: false
    signal cleared

    implicitHeight: MovieStyle.controlHeight + 4
    color: MovieStyle.text
    placeholderTextColor: MovieStyle.muted
    selectionColor: MovieStyle.accent
    selectedTextColor: MovieStyle.accentText
    font.family: MovieStyle.fontFamily
    font.pixelSize: MovieStyle.fontSize
    leftPadding: 12
    rightPadding: clearable ? 42 : 12
    selectByMouse: true
    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

    background: Rectangle {
        radius: MovieStyle.controlRadius
        color: "#c0141117"
        border.width: 1
        border.color: root.activeFocus ? MovieStyle.accent : MovieStyle.border
    }
    Loader {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        active: root.clearable
        sourceComponent: MovieIconButton {
            objectName: root.objectName + "Clear"
            width: 36
            height: 36
            visible: root.text.length > 0
            iconName: "x"
            text: "Clear search"
            onClicked: {
                root.clear();
                root.forceActiveFocus();
                root.cleared();
            }
        }
    }
}
