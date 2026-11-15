pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../ui"
import "../movies"

ColumnLayout {
    id: root
    required property var settings
    property var runners: []
    property bool inherit: false
    property bool busy: false
    property bool mangohud: false
    property bool umu: false
    property bool performance: true
    property bool showProton: true
    property bool supported: true
    property string storeId: "epic"
    signal edited(var settings)
    spacing: Theme.paddingLarge
    readonly property var inheritOption: inherit ? [
        {
            id: "inherit",
            name: "Use global default"
        }
    ] : []
    readonly property var fields: [
        {
            key: "overlay",
            label: "Performance overlay",
            object: "Overlay",
            options: inheritOption.concat([
                {
                    id: "off",
                    name: "Off"
                },
                {
                    id: "fps",
                    name: "FPS only"
                },
                {
                    id: "detailed",
                    name: "Detailed"
                }
            ])
        },
        {
            key: "position",
            label: "Overlay position",
            object: "Position",
            options: inheritOption.concat([
                {
                    id: "top-left",
                    name: "Top left"
                },
                {
                    id: "top-right",
                    name: "Top right"
                },
                {
                    id: "bottom-left",
                    name: "Bottom left"
                },
                {
                    id: "bottom-right",
                    name: "Bottom right"
                }
            ])
        },
        {
            key: "fpsLimit",
            label: "Frame rate limit",
            object: "FrameLimit",
            options: inheritOption.concat([
                {
                    id: 0,
                    name: "Unlimited"
                },
                {
                    id: 30,
                    name: "30 FPS"
                },
                {
                    id: 40,
                    name: "40 FPS"
                },
                {
                    id: 60,
                    name: "60 FPS"
                },
                {
                    id: 90,
                    name: "90 FPS"
                },
                {
                    id: 120,
                    name: "120 FPS"
                },
                {
                    id: 144,
                    name: "144 FPS"
                },
                {
                    id: 165,
                    name: "165 FPS"
                },
                {
                    id: 240,
                    name: "240 FPS"
                }
            ])
        },
        {
            key: "size",
            label: "Overlay size",
            object: "OverlaySize",
            options: inheritOption.concat([
                {
                    id: "small",
                    name: "Small"
                },
                {
                    id: "medium",
                    name: "Medium"
                },
                {
                    id: "large",
                    name: "Large"
                }
            ])
        }
    ]
    readonly property var runnerOptions: {
        let options = inheritOption.concat(runners);
        if (settings.proton && !options.some(option => option.id === settings.proton))
            options = options.concat([
                {
                    id: settings.proton,
                    name: "Unavailable · " + settings.proton.split("/").pop()
                }
            ]);
        return options;
    }
    function dismissPicker() {
        for (let index = 0; index < choices.count; ++index) {
            const picker = choices.itemAt(index)?.picker;
            if (picker?.popup.visible) {
                picker.popup.close();
                return true;
            }
        }
        if (proton.popup.visible) {
            proton.popup.close();
            return true;
        }
        return false;
    }
    function closePickers() {
        for (let index = 0; index < choices.count; ++index)
            choices.itemAt(index)?.picker.popup.close();
        proton.popup.close();
    }
    Repeater {
        id: choices
        model: root.performance ? root.fields : []
        GridLayout {
            id: field
            required property var modelData
            property alias picker: choice
            Layout.fillWidth: true
            columns: root.width >= 580 ? 2 : 1
            columnSpacing: Theme.paddingLarge
            rowSpacing: Theme.spacingMedium
            MovieText {
                text: field.modelData.label
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            MovieChoice {
                id: choice
                objectName: (root.inherit ? "game" : "default") + field.modelData.object + "Choice" + (root.inherit && root.storeId !== "epic" ? ":" + root.storeId : "")
                Layout.fillWidth: field.columns === 1
                Layout.preferredWidth: field.columns === 2 ? 300 : -1
                model: field.modelData.options
                textRole: "name"
                currentIndex: Math.max(0, model.findIndex(option => option.id === root.settings[field.modelData.key]))
                enabled: !root.busy && root.supported
                Accessible.name: field.modelData.label
                onActivated: {
                    const change = {};
                    change[field.modelData.key] = model[currentIndex].id;
                    root.edited(change);
                }
            }
        }
    }
    GridLayout {
        id: runnerField
        visible: root.showProton
        Layout.fillWidth: true
        columns: root.width >= 580 ? 2 : 1
        columnSpacing: Theme.paddingLarge
        rowSpacing: Theme.spacingMedium
        MovieText {
            text: "Proton version"
            Layout.fillWidth: true
        }
        MovieChoice {
            id: proton
            objectName: root.inherit ? "gameProtonChoice" : "defaultProtonChoice"
            Layout.fillWidth: runnerField.columns === 1
            Layout.preferredWidth: runnerField.columns === 2 ? 300 : -1
            model: root.runnerOptions
            textRole: "name"
            currentIndex: Math.max(0, root.runnerOptions.findIndex(option => option.id === root.settings.proton))
            enabled: !root.busy && root.umu
            Accessible.name: "Proton version"
            onActivated: root.edited({
                proton: root.runnerOptions[currentIndex].id
            })
        }
    }
}
