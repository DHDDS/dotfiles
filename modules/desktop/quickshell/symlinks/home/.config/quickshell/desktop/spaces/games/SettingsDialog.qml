pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import "../../ui"
import "../movies"

MovieStyle.Panel {
    id: root
    fullArea: true
    property var state: ({
            defaults: {},
            runners: []
        })
    property bool busy: false
    property string message: ""
    property string error: ""
    property string section: "performance"
    property var returnFocus: null
    readonly property var sections: [
        {
            id: "performance",
            name: "Performance",
            icon: "gauge"
        },
        {
            id: "steam",
            name: "Steam"
        },
        {
            id: "epic",
            name: "Epic Games"
        },
        {
            id: "gog",
            name: "GOG"
        },
        {
            id: "itch",
            name: "itch.io"
        },
        {
            id: "tools",
            name: "Tools",
            icon: "settings"
        }
    ]
    readonly property bool wide: width >= 640
    signal edited(var changes)
    signal actionRequested(string action, string store)
    signal downloadsRequested
    signal urlRequested(string url)
    Rectangle {
        parent: root.parent
        anchors.fill: parent
        z: 10000
        visible: root.visible
        color: "#b3000000"
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }
    objectName: "gamesSettingsPopup"
    modal: false
    palette.text: MovieStyle.text
    palette.windowText: MovieStyle.text
    palette.window: MovieStyle.background
    palette.base: MovieStyle.surface
    palette.button: MovieStyle.raised
    palette.buttonText: MovieStyle.text
    palette.highlight: MovieStyle.accentSurface
    palette.highlightedText: MovieStyle.text
    function dismissPicker() {
        if (navigation.popup.visible) {
            navigation.popup.close();
            return true;
        }
        return page.item?.dismissPicker ? page.item.dismissPicker() : false;
    }
    function closePickers() {
        navigation.popup.close();
        page.item?.closePickers?.();
    }
    onAboutToShow: returnFocus = parent.Window.window?.activeFocusItem || null
    onClosed: {
        closePickers();
        returnFocus?.forceActiveFocus();
        returnFocus = null;
    }
    onSectionChanged: closePickers()
    background: MovieStyle.PanelSurface {
        objectName: "gamesSettingsSurface"
    }
    contentItem: ColumnLayout {
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 12
            spacing: Theme.gap
            MovieStyle.PanelTitle {
                text: "Games settings"
                Layout.fillWidth: true
            }
            MovieStyle.PanelClose {
                text: "Close settings"
                onClicked: root.close()
            }
        }
        MovieChoice {
            id: navigation
            objectName: "gamesSettingsNavigation"
            visible: !root.wide
            Layout.fillWidth: true
            Layout.margins: Theme.padding
            model: root.sections
            textRole: "name"
            currentIndex: Math.max(0, root.sections.findIndex(item => item.id === root.section))
            Accessible.name: "Settings section"
            onActivated: root.section = model[currentIndex].id
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            Rectangle {
                visible: root.wide
                Layout.preferredWidth: 210
                Layout.fillHeight: true
                color: "transparent"
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.gap
                    spacing: Theme.spacingSmall
                    Repeater {
                        model: root.sections
                        ColumnLayout {
                            id: entry
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.spacingMedium
                            MovieText {
                                visible: entry.modelData.id === "steam" || entry.modelData.id === "tools"
                                text: entry.modelData.id === "steam" ? "STORES" : "MAINTENANCE"
                                color: MovieStyle.muted
                                font.pixelSize: MovieStyle.fontSize - 3
                                Layout.topMargin: Theme.padding
                                Layout.leftMargin: Theme.gap
                            }
                            MovieButton {
                                id: navButton
                                objectName: "settingsSection:" + entry.modelData.id
                                Layout.fillWidth: true
                                implicitHeight: Theme.pillHeight
                                checked: root.section === entry.modelData.id
                                idleColor: "transparent"
                                Accessible.name: entry.modelData.name
                                contentItem: RowLayout {
                                    spacing: Theme.gap
                                    MovieIcon {
                                        visible: !!entry.modelData.icon
                                        name: entry.modelData.icon || ""
                                        Layout.preferredWidth: Theme.iconSize
                                        Layout.preferredHeight: Theme.iconSize
                                        color: navButton.highlighted ? MovieStyle.text : MovieStyle.muted
                                    }
                                    Image {
                                        visible: !entry.modelData.icon
                                        source: entry.modelData.icon ? "" : Qt.resolvedUrl("stores/" + (entry.modelData.id === "epic" ? "epicgames" : entry.modelData.id) + ".svg")
                                        sourceSize.width: 40
                                        sourceSize.height: 40
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        fillMode: Image.PreserveAspectFit
                                        Accessible.ignored: true
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            brightness: 1
                                            colorization: 1
                                            colorizationColor: navButton.highlighted ? MovieStyle.text : MovieStyle.muted
                                        }
                                    }
                                    MovieText {
                                        text: entry.modelData.name
                                        color: MovieStyle.text
                                        Layout.fillWidth: true
                                    }
                                }
                                onClicked: root.section = entry.modelData.id
                            }
                        }
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                }
            }
            Rectangle {
                visible: root.wide
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: MovieStyle.border
            }
            ScrollArea {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ScrollBar.vertical: MovieScrollBar {}
                ScrollBar.horizontal: MovieScrollBar {}
                ColumnLayout {
                    width: scroll.availableWidth
                    spacing: Theme.paddingLarge
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.margins: root.wide ? Theme.paddingLarge : Theme.padding
                        Layout.maximumWidth: 840
                        spacing: Theme.paddingLarge
                        MovieText {
                            text: root.sections.find(item => item.id === root.section)?.name || "Performance"
                            font.pixelSize: MovieStyle.fontSize + 4
                            font.weight: Font.DemiBold
                        }
                        Loader {
                            id: page
                            Layout.fillWidth: true
                            sourceComponent: root.section === "performance" ? performancePage : root.section === "epic" ? epicPage : root.section === "tools" ? toolsPage : storePage
                        }
                    }
                }
            }
        }
        MovieText {
            objectName: "gamesSettingsStatus"
            Layout.fillWidth: true
            Layout.margins: Theme.padding
            font.pixelSize: MovieStyle.fontSize - 2
            text: root.error || (root.busy ? "Working…" : root.message || "Changes apply on the next launch.")
            color: root.error ? MovieStyle.danger : MovieStyle.muted
            wrapMode: Text.Wrap
            maximumLineCount: 3
        }
    }
    Component {
        id: performancePage
        LaunchSettings {
            objectName: "globalPerformanceSettings"
            settings: root.state.defaults || ({})
            runners: root.state.runners || []
            showProton: false
            busy: root.busy
            mangohud: !!root.state.mangohud
            onEdited: changes => root.edited(changes)
        }
    }
    Component {
        id: epicPage
        ColumnLayout {
            spacing: Theme.paddingLarge
            function dismissPicker() {
                return protonSettings.dismissPicker();
            }
            function closePickers() {
                protonSettings.closePickers();
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium
                MovieButton {
                    objectName: "gamesEpicConnect"
                    text: "Connect Epic"
                    iconName: "link"
                    enabled: !!root.state.epic && !!root.state.terminal && !root.busy
                    onClicked: root.actionRequested("epic_auth", "epic")
                }
                MovieButton {
                    text: "Refresh library"
                    iconName: "refresh-cw"
                    enabled: !root.busy
                    onClicked: root.actionRequested("refresh_store", "epic")
                }
                MovieButton {
                    text: "Notifications"
                    iconName: "bell"
                    onClicked: root.downloadsRequested()
                }
            }
            LaunchSettings {
                id: protonSettings
                Layout.fillWidth: true
                performance: false
                settings: root.state.defaults || ({})
                runners: root.state.runners || []
                umu: !!root.state.umu
                busy: root.busy
                onEdited: changes => root.edited(changes)
            }
        }
    }
    Component {
        id: storePage
        ColumnLayout {
            spacing: Theme.paddingLarge
            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium
                MovieButton {
                    objectName: "gamesStoreOpen:" + root.section
                    text: root.section === "steam" ? "Open Steam" : root.section === "gog" ? "Open Heroic" : root.state.itch ? "Open itch" : "Get the itch app"
                    iconName: "arrow-right"
                    enabled: !root.busy && (root.section === "steam" ? !!root.state.steam : root.section === "gog" ? !!root.state.heroic : true)
                    onClicked: root.section === "itch" && !root.state.itch ? root.urlRequested("https://itch.io/app") : root.actionRequested(root.section, root.section)
                }
                MovieButton {
                    text: "Refresh library"
                    iconName: "refresh-cw"
                    enabled: !root.busy
                    onClicked: root.actionRequested("refresh_store", root.section)
                }
            }
            ColumnLayout {
                visible: root.section === "steam" || root.section === "gog"
                Layout.fillWidth: true
                spacing: Theme.gap
                MovieText {
                    text: "Performance controls"
                    font.pixelSize: MovieStyle.fontSize
                    font.weight: Font.DemiBold
                }
                MovieButton {
                    objectName: "gamesPerformanceSetup:" + root.section
                    text: root.section === "gog" && !root.state.heroicHud ? "Install MangoHud for Heroic" : "Enable performance controls"
                    enabled: !root.busy && (root.section === "steam" ? !!root.state.steam && !!root.state.mangohud : !!root.state.heroic && (!!root.state.heroicHud || !!root.state.terminal && !!root.state.heroicExtension))
                    onClicked: root.actionRequested(root.section === "steam" ? "steam_setup" : root.state.heroicHud ? "gog_setup" : "heroic_mangohud", root.section)
                }
                MovieText {
                    Layout.fillWidth: true
                    text: root.section === "steam" ? "Quit Steam before enabling. Existing launch options are preserved." : "Quit Heroic before the initial setup. Later changes apply on the next launch."
                    color: MovieStyle.muted
                    wrapMode: Text.Wrap
                }
            }
        }
    }
    Component {
        id: toolsPage
        ColumnLayout {
            MovieButton {
                objectName: "gamesProtonPlus"
                text: "Open ProtonPlus"
                iconName: "settings"
                enabled: !!root.state.protonplus && !root.busy
                onClicked: root.actionRequested("protonplus", "")
            }
        }
    }
}
