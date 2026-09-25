import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/filmDays.js" as FilmDays
import "."

/**
 * Review of film days that differ between this device and the Drehzettel
 * plugin after the migration (P6). The migration kept the server values; here
 * the user sees both side by side and per day either keeps the server values
 * or sends the values from this device. Local copies are never deleted.
 *
 * items: FilmDaySync.loadConflicts() rows, plus state "resolvedLocal" /
 * "resolvedServer" once decided (the caller updates them).
 */
ColumnLayout {
    id: root

    width: parent ? parent.width : implicitWidth

    property var items: []
    property bool loading: false
    property bool busy: false
    /** function(projectId) → project name ("" when unknown). */
    property var projectNameOf: null
    /** function(projectId) → ISO currency of the project's customer ("" when unknown). */
    property var currencyOf: null

    signal resolveRequested(var item, bool useLocal)
    signal closeRequested()

    spacing: Kirigami.Units.smallSpacing

    readonly property int openCount: {
        var n = 0
        for (var i = 0; i < items.length; i++) {
            if (items[i].state === "ready" || items[i].state === "noEngagement") {
                n++
            }
        }
        return n
    }

    function fieldLabel(field) {
        switch (field) {
        case "breakMinutes": return i18n("Break")
        case "catering": return i18n("Catering")
        case "category": return i18n("Day category")
        case "dayType": return i18n("Day type")
        case "shootingDayNumber": return i18n("Production shooting day")
        case "productionDay": return i18n("Surcharge day")
        case "extraPayCents": return i18n("Extra pay / expenses")
        case "note": return i18n("Note")
        }
        return field
    }

    function valueText(field, value, projectId) {
        if (field === "breakMinutes") {
            return value === null || value === undefined ? i18n("Default") : i18np("%1 minute", "%1 minutes", value)
        }
        if (field === "catering") {
            return value ? i18n("Yes") : i18n("No")
        }
        if (field === "category") {
            switch (value) {
            case FilmDays.DayCategory.WORKDAY: return i18n("Workday")
            case FilmDays.DayCategory.SATURDAY: return i18n("Saturday")
            case FilmDays.DayCategory.SUNDAY: return i18n("Sunday")
            case FilmDays.DayCategory.HOLIDAY: return i18n("Holiday")
            }
            return i18n("Auto (from weekday)")
        }
        if (field === "dayType") {
            return value === FilmDays.DayType.TRAVEL ? i18n("Travel day") : i18n("Shooting day")
        }
        if (field === "shootingDayNumber") {
            return value === null || value === undefined ? i18n("Not set") : String(value)
        }
        if (field === "productionDay") {
            return value === null || value === undefined ? i18n("Automatic") : String(value)
        }
        if (field === "extraPayCents") {
            var text = Number((Number(value) || 0) / 100).toLocaleString(Qt.locale(), "f", 2)
            var currency = typeof root.currencyOf === "function" ? root.currencyOf(projectId) : ""
            return currency ? text + " " + currency : text
        }
        if (field === "note") {
            return value ? String(value) : "—"
        }
        return value === null || value === undefined ? "—" : String(value)
    }

    function dayTitle(item) {
        var parts = String(item.date).split("-")
        var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
        var dateText = isNaN(d.getTime()) ? item.date : d.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
        var name = typeof root.projectNameOf === "function" ? root.projectNameOf(item.projectId) : ""
        return name ? dateText + " · " + name : dateText
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: root.loading ? i18n("Loading the server values…")
            : (root.openCount > 0
               ? i18np("%1 film day has other values on the server than on this device. The server values are in use; pick per day which values to keep.",
                       "%1 film days have other values on the server than on this device. The server values are in use; pick per day which values to keep.",
                       root.openCount)
               : i18n("No differences left to review."))
    }

    QQC2.BusyIndicator {
        Layout.alignment: Qt.AlignHCenter
        visible: root.loading
        running: visible
    }

    Repeater {
        model: root.items
        delegate: ColumnLayout {
            readonly property var item: modelData
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing / 2

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                font.bold: true
                elide: Text.ElideRight
                text: root.dayTitle(item)
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: text.length > 0
                wrapMode: Text.WordWrap
                opacity: 0.8
                color: item.state === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                text: {
                    switch (item.state) {
                    case "same": return i18n("The server now has the same values. Nothing to decide.")
                    case "noEngagement": return i18n("No engagement for this project and day on the server any more. The values stay on this device.")
                    case "error": return i18n("The server values could not be loaded: %1", ApiErrors.text(item.error))
                    case "resolvedLocal": return i18n("The values from this device were sent to the server.")
                    case "resolvedServer": return i18n("The server values are kept.")
                    }
                    return ""
                }
            }

            GridLayout {
                Layout.fillWidth: true
                visible: item.state === "ready"
                columns: 3
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: 2

                PlasmaComponents3.Label {
                    text: ""
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                    text: i18n("This device")
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                    text: i18n("Server")
                }

                Repeater {
                    model: item.state === "ready" ? item.diff.length * 3 : 0
                    delegate: PlasmaComponents3.Label {
                        readonly property var row: item.diff[Math.floor(index / 3)]
                        readonly property int column: index % 3
                        Layout.fillWidth: column > 0
                        Layout.preferredWidth: column > 0 ? 1 : -1
                        wrapMode: column === 0 ? Text.NoWrap : Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        opacity: column === 0 ? 0.8 : 1
                        font.bold: column === 2
                        text: column === 0 ? root.fieldLabel(row.field)
                            : root.valueText(row.field, column === 1 ? row.local : row.server, item.projectId)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: item.state === "ready" || item.state === "noEngagement"
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Button {
                    visible: item.state === "ready"
                    enabled: !root.busy
                    text: i18n("Use values from this device")
                    icon.name: "cloud-upload"
                    onClicked: root.resolveRequested(item, true)
                }
                PlasmaComponents3.Button {
                    enabled: !root.busy
                    text: item.state === "ready" ? i18n("Keep server values") : i18n("OK")
                    onClicked: root.resolveRequested(item, false)
                }
            }
        }
    }

    PlasmaComponents3.Button {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.largeSpacing
        Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
        flat: true
        text: i18n("Back to the film day")
        onClicked: root.closeRequested()
    }
}
