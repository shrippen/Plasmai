import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "shared"

Kirigami.Page {
    id: page
    title: ""
    background: Rectangle { color: root.bgWindow }

    // Groups come from root's last async color-worker result (platform/colorWorker.js)
    // rather than being recomputed here — that computation is O(n²)-ish over the
    // catalog and belongs off the GUI thread, not in a page-local binding.
    readonly property bool supported: root.providerCapabilities.colorDistinction
    readonly property var customerGroups: page.supported ? root.customerColorGroups : []
    readonly property var projectGroups: page.supported ? root.projectColorGroups : []
    readonly property var activityGroups: page.supported ? root.activityColorGroups : []

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2
        clip: true
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: col
            width: parent.width
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout { Layout.fillWidth: true
                Kirigami.Heading { level: 1; text: i18n("Color maintenance"); Layout.fillWidth: true }
                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    text: i18n("Reload")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: { root.refreshAll(); root.rebuildColorMaps(true) }
                    QQC2.ToolTip.text: text; QQC2.ToolTip.visible: hovered
                }
            }

            Kirigami.PlaceholderMessage {
                Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing
                visible: !page.supported
                icon.name: "color-picker"
                text: i18n("Color maintenance is for Kimai")
                explanation: i18n("Only Kimai provides customer/project/activity colors to distinguish.")
            }

            Repeater {
                model: page.supported ? [
                    { title: i18n("Customers"), groups: page.customerGroups },
                    { title: i18n("Projects"), groups: page.projectGroups },
                    { title: i18n("Activities"), groups: page.activityGroups }
                ] : []
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing
                    visible: modelData.groups.length > 0

                    Kirigami.Separator { Layout.fillWidth: true }
                    Kirigami.Heading { level: 4; text: modelData.title; Layout.fillWidth: true }

                    Repeater {
                        model: modelData.groups
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.bottomMargin: Kirigami.Units.smallSpacing
                            spacing: 2

                            Repeater {
                                model: modelData.entries
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    Rectangle { width: 12; height: 12; radius: 3; color: modelData.original; border.width: 1; border.color: Qt.rgba(0,0,0,0.2) }
                                    Kirigami.Icon { source: "go-next"; opacity: 0.5; Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Kirigami.Units.iconSizes.small }
                                    Rectangle { width: 12; height: 12; radius: 3; color: modelData.display; border.width: 1; border.color: Qt.rgba(0,0,0,0.2) }
                                    QQC2.Label { text: modelData.name; elide: Text.ElideRight; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                                    QQC2.Label {
                                        text: modelData.keeper ? i18n("kept") : i18n("shifted")
                                        color: modelData.keeper ? root.clrTextMuted : root.clrWarning
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    }
                                }
                            }
                        }
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing
                visible: page.supported && page.customerGroups.length === 0 && page.projectGroups.length === 0 && page.activityGroups.length === 0
                text: i18n("No color clashes detected.")
                color: root.clrTextMuted
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing }
        }
    }
}
