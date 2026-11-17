import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."
import "Kante"
import "Controls" as Controls
import "../code/entityNames.js" as Names
import "../code/dateTimeFormat.js" as DTF
import "../code/offlineState.js" as OfflineState
import "../code/mileage.js" as Mileage

/**
 * The outbox of the offline layer (offlineOutbox.js), oldest first: what each change
 * is, whether it waits for the connection, was refused (retry / discard) or
 * meets a server change (overwrite / discard). Nothing leaves it silently.
 */
ColumnLayout {
    id: root

    /** Outbox.ops(session). */
    property var ops: []
    property var projects: []
    property var activities: []
    property var activitiesByProject: ({})

    /** Offline.groups: the changes parked for another server or account, one group each. */
    property var groups: []

    signal retryRequested(string opId)
    signal overwriteRequested(string opId)
    signal discardRequested(string opId)
    /** The group with this id goes to the address in use / is dropped (asked before). */
    signal adoptRequested(string id)
    signal discardGroupRequested(string id)

    spacing: Kirigami.Units.largeSpacing

    /** "Start – Destination · 28.09.26 · 12 km" of a trip change (a delete knows only its id). */
    function tripText(op) {
        var b = op.body || {}
        var bits = [Mileage.routeText(b.start || "", b.destination || "")]
        if (b.date) {
            bits.push(new Date(b.date + "T12:00:00").toLocaleDateString(Qt.locale(), Locale.ShortFormat))
        }
        if (b.distanceKm !== undefined && b.distanceKm !== null) {
            bits.push(i18n("%1 km", Mileage.displayKm(Mileage.tripKm(b))))
        }
        return bits.filter(function(x) { return !!x }).join(" · ")
    }

    /** "Project · Activity · 28.09. 09:00–10:00" from the change or the entry it changes. */
    function entryText(op) {
        if (op.kind === OfflineState.Op.TRIP_CREATE || op.kind === OfflineState.Op.TRIP_PATCH || op.kind === OfflineState.Op.TRIP_DELETE) {
            return tripText(op)
        }
        var f = op.kind === OfflineState.Op.CREATE ? op.fields : (op.base || {})
        if (op.kind === OfflineState.Op.FILM_DAY) {
            f = { project: op.projectId }
        }
        var ts = { project: f.project, activity: f.activity }
        var bits = [Names.displayProjectName(ts, root.projects),
                    Names.displayActivityName(ts, root.activities, root.activitiesByProject)]
        // A create carries stamps; the base of a change keeps ms (offlineOutbox.js baseOf).
        var beginMs = op.kind === OfflineState.Op.CREATE ? DTF.stampMs(f.begin) : f.begin
        if (beginMs) {
            var b = new Date(beginMs)
            var span = b.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " "
                + b.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
            var end = op.kind === OfflineState.Op.CREATE ? f.end : (op.fields && op.fields.end)
            if (end) {
                span += "–" + new Date(DTF.stampMs(end)).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
            }
            bits.push(span)
        }
        return bits.filter(function(b) { return !!b }).join(" · ")
    }

    /** One change: what it is and why it waits; the buttons unless the row is only shown. */
    component OpRow: ColumnLayout {
        id: row
        property var op: ({})
        property bool readOnly: false
        readonly property bool stuck: op.state !== OfflineState.State.PENDING

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            Layout.fillWidth: true
            text: ApiErrors.opKindText(row.op)
            font.bold: true
            wrapMode: Text.WordWrap
        }
        Controls.Label {
            Layout.fillWidth: true
            text: root.entryText(row.op)
            wrapMode: Text.WordWrap
        }
        Controls.Label {
            Layout.fillWidth: true
            text: ApiErrors.opStateText(row.op)
            color: row.stuck ? KanteStyle.negativeTextColor : KanteStyle.mutedTextColor
            wrapMode: Text.WordWrap
        }
        RowLayout {
            visible: !row.readOnly
            spacing: Kirigami.Units.smallSpacing
            Controls.Button {
                visible: row.op.state === OfflineState.State.FAILED
                text: i18n("Retry")
                onClicked: root.retryRequested(row.op.opId)
            }
            Controls.Button {
                visible: row.op.state === OfflineState.State.CONFLICT
                text: i18n("Overwrite")
                onClicked: root.overwriteRequested(row.op.opId)
            }
            Controls.Button {
                text: i18n("Discard")
                onClicked: root.discardRequested(row.op.opId)
            }
        }
    }

    /**
     * Changes parked for another server or account: what and for whom, the changes themselves
     * (read only) on demand, "Send here" only for the same account on another address, "Discard";
     * both ask once, naming the addresses.
     */
    component GroupBlock: ColumnLayout {
        id: block
        property var group: ({})
        // "", "adopt" or "discard": what the question below is about.
        property string asking: ""
        property bool opened: false

        objectName: "heldGroup"
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            objectName: "heldGroupTitle"
            Layout.fillWidth: true
            text: ApiErrors.heldGroupText(block.group)
            font.bold: true
            wrapMode: Text.WordWrap
        }
        Controls.Label {
            objectName: "heldHint"
            Layout.fillWidth: true
            visible: text !== ""
            text: ApiErrors.heldHint(block.group)
            color: KanteStyle.mutedTextColor
            wrapMode: Text.WordWrap
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            visible: block.asking === ""
            Controls.Button {
                objectName: "heldToggle"
                text: block.opened ? i18n("Hide") : i18n("Show")
                onClicked: block.opened = !block.opened
            }
            Controls.Button {
                objectName: "adoptButton"
                visible: block.group.canAdopt
                text: i18n("Send here")
                onClicked: block.asking = "adopt"
            }
            Controls.Button {
                objectName: "discardGroupButton"
                text: i18n("Discard")
                onClicked: block.asking = "discard"
            }
        }
        ColumnLayout {
            objectName: "confirmRow"
            Layout.fillWidth: true
            visible: block.asking !== ""
            spacing: Kirigami.Units.smallSpacing
            Controls.Label {
                objectName: "confirmText"
                Layout.fillWidth: true
                text: block.asking === "adopt" ? ApiErrors.adoptQuestion(block.group) : ApiErrors.discardGroupQuestion(block.group)
                wrapMode: Text.WordWrap
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Controls.Button {
                    objectName: "confirmButton"
                    text: block.asking === "adopt" ? i18n("Send here") : i18n("Discard")
                    onClicked: {
                        const adopt = block.asking === "adopt"
                        block.asking = ""
                        if (adopt) {
                            root.adoptRequested(block.group.id)
                        } else {
                            root.discardGroupRequested(block.group.id)
                        }
                    }
                }
                Controls.Button {
                    objectName: "cancelButton"
                    text: i18n("Cancel")
                    onClicked: block.asking = ""
                }
            }
        }
        ColumnLayout {
            objectName: "heldOps"
            Layout.fillWidth: true
            visible: block.opened
            spacing: Kirigami.Units.largeSpacing
            Repeater {
                model: block.opened ? block.group.ops : []
                OpRow {
                    required property var modelData
                    op: modelData
                    readOnly: true
                }
            }
        }
    }

    Controls.Label {
        objectName: "emptyLabel"
        visible: root.ops.length === 0 && root.groups.length === 0
        Layout.fillWidth: true
        text: i18n("Everything is synced.")
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.ops
        OpRow {
            required property var modelData
            op: modelData
        }
    }

    Repeater {
        model: root.groups
        GroupBlock {
            required property var modelData
            group: modelData
        }
    }
}
