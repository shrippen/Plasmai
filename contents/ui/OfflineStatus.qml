import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Kante"
import "Controls" as Controls

/**
 * Offline and sync state of the offline layer (offline.js), shared by the
 * Plasmoid and the app: "Offline · as of 12:04", changes not synced yet,
 * changes the server did not take. Hidden when online with nothing waiting.
 */
RowLayout {
    id: root

    property bool offline: false
    /** When the shown state came from the server (ms, 0 = never). */
    property double stateAt: 0
    /** Changes in the outbox. */
    property int unsynced: 0
    /** Of those: refused by the server or changed there meanwhile (need a decision). */
    property int stuck: 0
    /** "Show" (the list of waiting changes); off where that list is shown already. */
    property bool showDetails: true

    signal detailsRequested()

    visible: offline || unsynced > 0
    spacing: Kirigami.Units.smallSpacing

    function stateTime() {
        var at = new Date(root.stateAt)
        var time = at.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
        return at.toDateString() === new Date().toDateString()
            ? time : at.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " " + time
    }

    function text() {
        var parts = []
        if (root.offline) {
            parts.push(root.stateAt > 0 ? i18n("Offline · as of %1", stateTime()) : i18n("Offline"))
        }
        if (root.stuck > 0) {
            parts.push(i18np("%1 change needs your decision", "%1 changes need your decision", root.stuck))
        } else if (root.unsynced > 0) {
            parts.push(i18np("%1 change not synced yet", "%1 changes not synced yet", root.unsynced))
        }
        return parts.join(" · ")
    }

    Kirigami.Icon {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small
        source: root.stuck > 0 ? "dialog-warning" : (root.offline ? "network-disconnect" : "view-refresh")
    }

    Controls.Label {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: root.text()
        wrapMode: Text.WordWrap
        color: root.stuck > 0 ? KanteStyle.negativeTextColor : KanteStyle.textColor
    }

    Controls.Button {
        visible: root.showDetails && root.unsynced > 0
        text: i18n("Show")
        onClicked: root.detailsRequested()
    }
}
