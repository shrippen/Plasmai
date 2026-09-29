import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."
import "Kante"
import "Controls" as Controls
import "../code/kimaiApi.js" as KimaiApi
import "../code/dateTimeFormat.js" as DTF
import "../code/offline.js" as Offline

/**
 * The outbox of the offline layer (offline.js), oldest first: what each change
 * is, whether it waits for the connection, was refused (retry / discard) or
 * meets a server change (overwrite / discard). Nothing leaves it silently.
 */
ColumnLayout {
    id: root

    /** Offline.ops(session). */
    property var ops: []
    property var projects: []
    property var activities: []
    property var activitiesByProject: ({})

    signal retryRequested(string opId)
    signal overwriteRequested(string opId)
    signal discardRequested(string opId)

    spacing: Kirigami.Units.largeSpacing

    function kindText(op) {
        if (op.kind === Offline.Op.CREATE) {
            return op.fields.end ? i18n("New entry") : i18n("Timer started")
        }
        if (op.kind === Offline.Op.PATCH) {
            var keys = Object.keys(op.fields || {})
            return keys.length === 1 && keys[0] === "end" ? i18n("Timer stopped") : i18n("Entry changed")
        }
        if (op.kind === Offline.Op.DELETE) {
            return i18n("Entry deleted")
        }
        if (op.kind === Offline.Op.FILM_DAY) {
            return i18n("Film day details of %1",
                        new Date(op.dateStr + "T12:00:00").toLocaleDateString(Qt.locale(), Locale.ShortFormat))
        }
        return op.kind
    }

    /** "Project · Activity · 28.09. 09:00–10:00" from the change or the entry it changes. */
    function entryText(op) {
        var f = op.kind === Offline.Op.CREATE ? op.fields : (op.base || {})
        if (op.kind === Offline.Op.FILM_DAY) {
            f = { project: op.projectId }
        }
        var ts = { project: f.project, activity: f.activity }
        var bits = [KimaiApi.displayProjectName(ts, root.projects),
                    KimaiApi.displayActivityName(ts, root.activities, root.activitiesByProject)]
        // A create carries stamps; the base of a change keeps ms (offline.js baseOf).
        var beginMs = op.kind === Offline.Op.CREATE ? DTF.stampMs(f.begin) : f.begin
        if (beginMs) {
            var b = new Date(beginMs)
            var span = b.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " "
                + b.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
            var end = op.kind === Offline.Op.CREATE ? f.end : (op.fields && op.fields.end)
            if (end) {
                span += "–" + new Date(DTF.stampMs(end)).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
            }
            bits.push(span)
        }
        return bits.filter(function(b) { return !!b }).join(" · ")
    }

    function stateText(op) {
        if (op.state === Offline.State.FAILED) {
            return i18n("Not accepted: %1", (op.error && op.error.detail) || ApiErrors.text(op.error))
        }
        if (op.state === Offline.State.CONFLICT) {
            return i18n("Changed on the server meanwhile (%1). Overwrite it with this change, or discard this change?",
                        op.error ? op.error.detail : "")
        }
        return i18n("Waiting for the connection")
    }

    Controls.Label {
        visible: root.ops.length === 0
        Layout.fillWidth: true
        text: i18n("Everything is synced.")
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.ops

        ColumnLayout {
            id: row
            required property var modelData
            readonly property bool stuck: modelData.state !== Offline.State.PENDING

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                Layout.fillWidth: true
                text: root.kindText(row.modelData)
                font.bold: true
                wrapMode: Text.WordWrap
            }
            Controls.Label {
                Layout.fillWidth: true
                text: root.entryText(row.modelData)
                wrapMode: Text.WordWrap
            }
            Controls.Label {
                Layout.fillWidth: true
                text: root.stateText(row.modelData)
                color: row.stuck ? KanteStyle.negativeTextColor : KanteStyle.mutedTextColor
                wrapMode: Text.WordWrap
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Controls.Button {
                    visible: row.modelData.state === Offline.State.FAILED
                    text: i18n("Retry")
                    onClicked: root.retryRequested(row.modelData.opId)
                }
                Controls.Button {
                    visible: row.modelData.state === Offline.State.CONFLICT
                    text: i18n("Overwrite")
                    onClicked: root.overwriteRequested(row.modelData.opId)
                }
                Controls.Button {
                    text: i18n("Discard")
                    onClicked: root.discardRequested(row.modelData.opId)
                }
            }
        }
    }
}
