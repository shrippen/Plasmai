import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "."

QQC2.ItemDelegate {
    id: root

    property color customerColor: "#d2d6de"
    property string colorCategory: ""
    property var entityId: null
    property string titleText: ""
    property string subtitleText: ""
    property string tooltipText: ""
    property bool showPlayIcon: true
    property bool rowEnabled: true
    /** Short transient right-side hint (e.g. when clicking an already-running activity). */
    property bool runningHintVisible: false
    property string runningHintText: ""
    property string runningHintCounterText: ""
    /** Overflow on Recent rows only — favorites stay one-tap start. */
    property bool showHistoryActions: false
    property bool canEditStopped: false
    property bool canDeleteEntry: false
    property bool canSplitEntry: false
    property bool ignoreNextRowClick: false

    signal editRequested()
    signal deleteRequested()
    signal splitRequested()
    /** Row body (not the overflow). Favorites and Recents bind onRowActivated. */
    signal rowActivated()

    enabled: rowEnabled
    hoverEnabled: true
    Accessible.role: Accessible.ListItem
    Accessible.name: titleText
    Accessible.description: i18n("Starts or switches this activity")
    implicitHeight: Math.max(contentItem.implicitHeight + topPadding + bottomPadding,
                             TouchUi.rowMinHeight)
    // Fill-width rows: a tiny implicitWidth so eliding labels / Menu do not
    // stretch the flyout Flickable (horizontal scrollbar + early ellipsis).
    implicitWidth: 1
    Layout.fillWidth: true
    topPadding: TouchUi.listRowPadding
    bottomPadding: TouchUi.listRowPadding
    clip: true

    QQC2.ToolTip.visible: root.hovered && root.tooltipText.length > 0
                          && !historyButton.hovered
    QQC2.ToolTip.text: root.tooltipText
    QQC2.ToolTip.delay: 600

    onClicked: {
        if (ignoreNextRowClick
                || (historyButton.visible && (historyButton.hovered || historyButton.pressed))
                || historyMenu.visible) {
            return
        }
        root.rowActivated()
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        CustomerColorDot {
            customerColor: root.customerColor
            colorCategory: root.colorCategory
            entityId: root.entityId
            sizeFactor: TouchUi.active ? 0.55 : 0.45
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
        }

        Kirigami.Icon {
            visible: root.showPlayIcon
            Layout.preferredWidth: TouchUi.iconSize
            Layout.preferredHeight: TouchUi.iconSize
            source: "media-playback-start"
            opacity: root.enabled ? 1 : 0.5
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.minimumWidth: 0
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: root.titleText
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.subtitleText.length > 0
                text: root.subtitleText
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.7
                elide: Text.ElideRight
            }
        }

        Item {
            id: runningHintBox
            // Overlay: take leftover height, never increase the row's implicitHeight.
            Layout.preferredWidth: root.runningHintVisible ? Kirigami.Units.gridUnit * 6 : 0
            Layout.maximumWidth: root.runningHintVisible ? Kirigami.Units.gridUnit * 6 : 0
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            Layout.preferredHeight: 0
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 0
            clip: true
            visible: root.runningHintVisible
            opacity: root.runningHintVisible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: 0

                PlasmaComponents3.Label {
                    id: runningHintTop
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.NoWrap
                    text: runningHintText
                    font.bold: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.positiveTextColor
                    elide: Text.ElideRight
                }

                PlasmaComponents3.Label {
                    id: runningHintBottom
                    Layout.fillWidth: true
                    visible: runningHintCounterText.length > 0
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.NoWrap
                    text: runningHintCounterText
                    font.family: "monospace"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.positiveTextColor
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            id: historyButton
            property bool hovered: historyMouseArea.containsMouse
            property bool pressed: historyMouseArea.pressed
            visible: root.showHistoryActions
                     && (root.canEditStopped || root.canDeleteEntry || root.canSplitEntry)
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: TouchUi.iconSize + Kirigami.Units.smallSpacing * 2
            Layout.maximumWidth: TouchUi.iconSize + Kirigami.Units.smallSpacing * 2
            Layout.minimumWidth: TouchUi.iconSize + Kirigami.Units.smallSpacing * 2
            Layout.preferredHeight: TouchUi.iconSize + Kirigami.Units.smallSpacing * 2
            Accessible.role: Accessible.Button
            Accessible.name: i18n("Entry actions")

            Kirigami.Icon {
                anchors.centerIn: parent
                width: TouchUi.iconSize
                height: TouchUi.iconSize
                source: "overflow-menu"
                opacity: root.rowEnabled ? 1.0 : 0.4
                color: root.hovered || historyMouseArea.containsMouse
                       ? Kirigami.Theme.textColor
                       : Kirigami.Theme.disabledTextColor
            }

            MouseArea {
                id: historyMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: function(mouse) {
                    root.ignoreNextRowClick = true
                    Qt.callLater(function() {
                        root.ignoreNextRowClick = false
                    })
                }
                onClicked: historyMenu.popup()
            }

            QQC2.ToolTip.visible: historyButton.hovered
            QQC2.ToolTip.text: i18n("Entry actions")
            QQC2.ToolTip.delay: 600
        }
    }

    QQC2.Menu {
        id: historyMenu
        QQC2.MenuItem {
            visible: root.canEditStopped
            height: visible ? implicitHeight : 0
            text: i18n("Edit entry")
            icon.name: "document-edit"
            onTriggered: root.editRequested()
        }
        QQC2.MenuItem {
            visible: root.canSplitEntry
            height: visible ? implicitHeight : 0
            text: i18n("Split entry")
            icon.name: "edit-cut"
            onTriggered: root.splitRequested()
        }
        QQC2.MenuItem {
            visible: root.canDeleteEntry
            height: visible ? implicitHeight : 0
            text: i18n("Delete entry")
            icon.name: "edit-delete"
            onTriggered: root.deleteRequested()
        }
    }
}
