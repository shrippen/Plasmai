import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Kante"
import "Controls" as Controls
import "../code/offlineState.js" as OfflineState

/**
 * Offline and sync state of the offline layer (offline.js), shared by the
 * Plasmoid and the app: "Offline · as of 12:04", changes not synced yet,
 * changes the server did not take, a problem with the file of the waiting
 * changes. Hidden when online with nothing waiting and no such problem.
 * Kante: a KanteCallout with "Show" as its action; System: icon, text, button.
 */
Item {
    id: root

    property bool offline: false
    /** When the shown state came from the server (ms, 0 = never). */
    property double stateAt: 0
    /** Changes in the outbox. */
    property int unsynced: 0
    /** Of those: refused by the server or changed there meanwhile (need a decision). */
    property int stuck: 0
    /** Changes parked for another server or account (they wait for a decision there). */
    property int held: 0
    /** OfflineState.StorageError: what is wrong with the file of the waiting changes. */
    property string storageError: OfflineState.StorageError.NONE
    /** "Show" (the list of waiting changes); off where that list is shown already. */
    property bool showDetails: true

    signal detailsRequested()

    readonly property bool storageProblem: storageError !== OfflineState.StorageError.NONE

    visible: offline || unsynced > 0 || held > 0 || storageProblem
    implicitWidth: KanteStyle.active ? callout.implicitWidth : systemRow.implicitWidth
    implicitHeight: KanteStyle.active ? callout.implicitHeight : systemRow.implicitHeight

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
        if (root.held > 0) {
            parts.push(ApiErrors.heldStatusText(root.held))
        }
        if (root.storageProblem) {
            parts.push(ApiErrors.storageText(root.storageError))
        }
        return parts.join(" · ")
    }

    // Kante: stuck changes and storage problems warn, anything else informs.
    KanteCallout {
        id: callout
        anchors.left: parent.left
        anchors.right: parent.right
        visible: KanteStyle.active
        kind: root.stuck > 0 || root.held > 0 || root.storageProblem ? KanteCallout.Kind.Warn : KanteCallout.Kind.Info
        text: root.text()

        Controls.Button {
            visible: root.showDetails && (root.unsynced > 0 || root.held > 0)
            text: i18n("Show")
            onClicked: root.detailsRequested()
        }
    }

    RowLayout {
        id: systemRow
        anchors.fill: parent
        visible: !KanteStyle.active
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
            source: root.stuck > 0 || root.held > 0 || root.storageProblem ? "dialog-warning" : (root.offline ? "network-disconnect" : "view-refresh")
        }

        Controls.Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.text()
            wrapMode: Text.WordWrap
            color: root.stuck > 0 || root.held > 0 || root.storageProblem ? KanteStyle.negativeTextColor : KanteStyle.textColor
        }

        Controls.Button {
            visible: root.showDetails && (root.unsynced > 0 || root.held > 0)
            text: i18n("Show")
            onClicked: root.detailsRequested()
        }
    }
}
