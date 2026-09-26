import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "."
import "../Kante"

QQC2.ItemDelegate {
    id: root

    property color customerColor: PlasmaiColors.entityFallback
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
    property bool canPin: false
    /** Recent rows: "Log trip" for this entry (kimai-anfahrten plugin present). */
    property bool canLogTrip: false
    property bool isPinned: false
    property bool ignoreNextRowClick: false

    enum Presentation {
        List,
        Tile
    }

    /** Kante only: favorites as tiles, Recent as a time line. System ignores it. */
    property int presentation: ActivityListRow.Presentation.List
    /** Kante time line: "07:42 – 09:40", "Thu 10:00", … ("" = none). */
    property string timeText: ""
    /** Kante time line: duration in h:mm ("" = none). */
    property string durationText: ""
    readonly property bool kanteTile: KanteStyle.active && presentation === ActivityListRow.Presentation.Tile
    readonly property bool kanteLine: KanteStyle.active && presentation === ActivityListRow.Presentation.List

    signal editRequested()
    signal deleteRequested()
    signal splitRequested()
    signal pinRequested()
    signal tripRequested()
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

    // Kante: tiles are cards with the customer color on top, time line rows
    // show a sunken tint on hover. The style's highlight stays hidden.
    KanteCard {
        z: -1
        anchors.fill: parent
        visible: root.kanteTile
        color: root.hovered ? KanteStyle.sunkenColor : KanteStyle.cardColor
        barColor: root.customerColor
        chamfer: KanteStyle.chamferSmall
    }
    Rectangle {
        z: -1
        anchors.fill: parent
        visible: root.kanteLine && (root.hovered || root.visualFocus)
        color: KanteStyle.sunkenColor
    }
    Binding {
        target: root.background
        property: "opacity"
        value: 0
        when: KanteStyle.active && root.background !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root
        property: "leftPadding"
        value: Kirigami.Units.smallSpacing * 2
        when: root.kanteTile
        restoreMode: Binding.RestoreBindingOrValue
    }

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

        QQC2.Label {
            visible: root.kanteLine && root.timeText.length > 0
            Layout.preferredWidth: Math.ceil(timeMetrics.width) + Kirigami.Units.smallSpacing
            text: root.timeText
            font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, false)
            color: KanteStyle.mutedTextColor
            elide: Text.ElideRight
        }

        Rectangle {
            visible: root.kanteLine
            Layout.preferredWidth: 3
            Layout.fillHeight: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            color: root.customerColor
        }

        CustomerColorDot {
            visible: !KanteStyle.active
            customerColor: root.customerColor
            sizeFactor: TouchUi.active ? 0.55 : 0.45
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
        }

        Kirigami.Icon {
            visible: root.showPlayIcon && !root.kanteLine
            // Small like in the Plasmoid; the row action icons keep the larger touch size.
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: "media-playback-start"
            color: KanteStyle.active ? KanteStyle.positiveTextColor : "transparent"
            opacity: root.enabled ? 1 : 0.5
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.minimumWidth: 0
            spacing: 0

            QQC2.Label {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: !root.kanteLine
                text: root.titleText
                font.weight: root.kanteTile ? Font.DemiBold : KanteStyle.defaultFont.weight
                elide: Text.ElideRight
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.subtitleText.length > 0 && !root.kanteLine
                text: root.subtitleText
                font.pointSize: KanteStyle.smallFont.pointSize
                color: KanteStyle.active ? KanteStyle.mutedTextColor : Kirigami.Theme.textColor
                opacity: KanteStyle.active ? 1 : 0.7
                elide: Text.ElideRight
            }

            // Kante time line: "Activity · Project" on one line.
            QQC2.Label {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.kanteLine
                textFormat: Text.StyledText
                text: "<b>" + root.escaped(root.titleText) + "</b>"
                    + (root.subtitleText.length > 0
                       ? "<font color=\"" + KanteStyle.mutedTextColor + "\"> · " + root.escaped(root.subtitleText) + "</font>"
                       : "")
                elide: Text.ElideRight
            }
        }

        QQC2.Label {
            visible: root.kanteLine && root.durationText.length > 0 && !root.runningHintVisible
            text: root.durationText
            font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, false)
            color: KanteStyle.textColor
            horizontalAlignment: Text.AlignRight
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

                QQC2.Label {
                    id: runningHintTop
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.NoWrap
                    text: runningHintText
                    font.bold: true
                    font.pointSize: KanteStyle.smallFont.pointSize
                    color: KanteStyle.positiveTextColor
                    elide: Text.ElideRight
                }

                QQC2.Label {
                    id: runningHintBottom
                    Layout.fillWidth: true
                    visible: runningHintCounterText.length > 0
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.NoWrap
                    text: runningHintCounterText
                    font.family: KanteStyle.monoFamily
                    font.bold: true
                    font.pointSize: KanteStyle.smallFont.pointSize
                    color: KanteStyle.positiveTextColor
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            id: historyButton
            property bool hovered: historyMouseArea.containsMouse
            property bool pressed: historyMouseArea.pressed
            visible: root.showHistoryActions
                     && (root.canEditStopped || root.canDeleteEntry || root.canSplitEntry || root.canPin)
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
                       ? KanteStyle.textColor
                       : KanteStyle.disabledTextColor
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
                // Anchor to the button: popup() without arguments follows the mouse cursor, which is
                // meaningless for touch input (Plasma Mobile) and lands in the window corner there.
                onClicked: historyMenu.popup(historyButton, historyButton.width - historyMenu.implicitWidth, historyButton.height)
            }

            QQC2.ToolTip.visible: historyButton.hovered && !Kirigami.Settings.isMobile
            QQC2.ToolTip.text: i18n("Entry actions")
            QQC2.ToolTip.delay: 600
        }
    }

    // Widest time label, so the colored bars line up: "00:00 – 00:00".
    TextMetrics {
        id: timeMetrics
        font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, false)
        text: "00:00 – 00:00"
    }

    function escaped(text) {
        return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    KantePopupSkin { popup: historyMenu }

    QQC2.Menu {
        id: historyMenu
        QQC2.MenuItem {
            visible: root.canPin
            height: visible ? implicitHeight : 0
            text: root.isPinned ? i18n("Unpin from favorites") : i18n("Pin as favorite")
            icon.name: root.isPinned ? "bookmarks" : "bookmark-new"
            onTriggered: root.pinRequested()
        }
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
            visible: root.canLogTrip
            height: visible ? implicitHeight : 0
            text: i18n("Log trip")
            icon.name: "mark-location"
            onTriggered: root.tripRequested()
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
