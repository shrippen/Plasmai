import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/mileage.js" as Mileage
import "."
import "Kante"
import "KantePlasma"

/**
 * Open trip suggestions of the kimai-anfahrten plugin (detected from
 * Dawarich tracks): route, distance, time, and "Accept" / "Dismiss".
 * The caller does the requests (acceptRequested / dismissRequested) and
 * removes the row when it succeeded.
 */
ColumnLayout {
    id: root

    /** GET /api/mileage/suggestions rows. */
    property var suggestions: []
    /** Rows shown at most (0 = all). */
    property int maxRows: 0
    property bool busy: false
    property bool canEdit: true
    /** GET /api/mileage/meta body for purpose labels, or null. */
    property var meta: null

    signal acceptRequested(var suggestion)
    signal dismissRequested(var suggestion)
    signal editRequested(var suggestion)

    spacing: 0

    readonly property var purposeFallback: ({
        "business": i18n("Business trip"),
        "commute": i18n("Commute"),
        "private": i18n("Private")
    })
    readonly property int shownCount: maxRows > 0 ? Math.min(maxRows, suggestions.length) : suggestions.length

    function timeText(stamp) {
        var d = new Date(String(stamp || ""))
        if (isNaN(d.getTime())) {
            return ""
        }
        return d.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " " + d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
    }

    Repeater {
        model: root.shownCount
        delegate: RowLayout {
            readonly property var s: root.suggestions[index]
            Layout.fillWidth: true
            Layout.minimumHeight: TouchUi.rowMinHeight
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "mark-location"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                Layout.alignment: Qt.AlignVCenter
                opacity: 0.8
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Mileage.routeText(s ? s.from : "", s ? s.to : "") || i18n("Detected trip")
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pointSize: KanteStyle.smallFont.pointSize
                    opacity: 0.7
                    text: {
                        if (!s) {
                            return ""
                        }
                        var bits = [root.timeText(s.start),
                                    i18n("%1 km", Mileage.formatKm(s.distanceKm)),
                                    Mileage.labelOf(root.meta ? root.meta.purposes : null, s.purpose, root.purposeFallback)]
                        return bits.filter(function(b) { return b.length > 0 }).join(" · ")
                    }
                }
            }

            KantePlasmaToolButton {
                visible: root.canEdit
                enabled: !root.busy
                icon.name: "dialog-ok-apply"
                text: i18n("Accept")
                display: TouchUi.active ? QQC2.AbstractButton.TextBesideIcon : QQC2.AbstractButton.IconOnly
                onClicked: root.acceptRequested(s)
                PlasmaComponents3.ToolTip.text: i18n("Add this trip to the logbook")
                PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            KantePlasmaToolButton {
                visible: root.canEdit
                enabled: !root.busy
                icon.name: "document-edit"
                text: i18n("Edit and accept")
                display: QQC2.AbstractButton.IconOnly
                onClicked: root.editRequested(s)
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            KantePlasmaToolButton {
                visible: root.canEdit
                enabled: !root.busy
                icon.name: "edit-delete"
                text: i18n("Dismiss")
                display: QQC2.AbstractButton.IconOnly
                onClicked: root.dismissRequested(s)
                PlasmaComponents3.ToolTip.text: i18n("Dismiss this detected trip")
                PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: root.maxRows > 0 && root.suggestions.length > root.maxRows
        font.pointSize: KanteStyle.smallFont.pointSize
        opacity: 0.7
        text: i18np("+%1 more detected trip", "+%1 more detected trips", root.suggestions.length - root.maxRows)
    }
}
