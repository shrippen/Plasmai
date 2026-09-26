import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../../contents/code/mileage.js" as Mileage
import "../../contents/code/dateTimeFormat.js" as DTF
import "."
import "../Kante"

/**
 * One trip of the Kimai MileageBundle (kimai-anfahrten): new, edit, or
 * linked to a Kimai entry. The caller loads it with load(form, original,
 * linkedText) and sends the body it gets from saveRequested() (mileage.js
 * builds it: every set field for a new trip, only changed keys for an edit).
 * Field errors of the plugin (400 {"errors": {…}}) come back through
 * serverErrors.
 */
ColumnLayout {
    id: root

    width: parent ? parent.width : implicitWidth

    property bool busy: false
    property bool configured: true
    property bool connectionOk: true
    /** GET /api/mileage/ping body: profile (commute distance), permissions, locked months, features. */
    property var ping: null
    /** GET /api/mileage/meta body ({purposes, vehicles}) or null. */
    property var meta: null
    /** GET /api/mileage/vehicles ([{id, name, type, active}]). */
    property var vehicles: []
    /** Plugin field errors of the last save: { field: message }. */
    property var serverErrors: ({})
    property string errorText: ""
    /** Human-readable Kimai entry the trip is linked to ("" = none). */
    property string linkedText: ""

    /** Form of mileage.js (id, project, timesheet are kept from here). */
    property var baseForm: Mileage.emptyForm(null, "")
    /** Trip JSON when editing, null for a new trip. */
    property var original: null
    readonly property bool editing: original !== null && original !== undefined
    readonly property bool canDelete: editing && Mileage.can(ping, "deleteOwn")

    /** Showing a detected trip before accepting it: date, route and times are as detected. */
    property bool suggestionMode: false

    /** body: POST/PATCH body (mileage.js toApiBody); form: the sheet's form (for accepting a suggestion). */
    signal saveRequested(var body, var tripId, var form)
    signal deleteRequested(var tripId)
    signal cancelled()

    readonly property var purposeFallback: ({
        "business": i18n("Business trip"),
        "commute": i18n("Commute"),
        "private": i18n("Private")
    })
    readonly property var vehicleFallback: ({
        "own_car": i18n("Own car"),
        "rental_car": i18n("Rental car"),
        "company_car": i18n("Company car"),
        "motorcycle": i18n("Motorcycle / scooter"),
        "bicycle": i18n("Bicycle"),
        "public_transport": i18n("Public transport"),
        "other": i18n("Other")
    })
    readonly property var purposeOptions: Mileage.options(meta ? meta.purposes : null, Mileage.PURPOSES, purposeFallback)
    readonly property var vehicleOptions: Mileage.options(meta ? meta.vehicles : null, Mileage.VEHICLES, vehicleFallback)
    readonly property var assignedVehicleOptions: {
        var out = [{ value: null, label: i18n("No specific vehicle") }]
        for (var i = 0; i < (vehicles || []).length; i++) {
            var v = vehicles[i]
            if (v && (v.active !== false || String(v.id) === String(baseForm.vehicleId))) {
                out.push({ value: v.id, label: v.licensePlate ? (v.name + " · " + v.licensePlate) : String(v.name || v.id) })
            }
        }
        return out
    }

    readonly property var localErrors: Mileage.validateForm(currentForm(), ping)
    readonly property bool formValid: !Mileage.hasErrors(localErrors)

    function pad2(n) {
        return (n < 10 ? "0" : "") + n
    }

    function indexOfValue(opts, value) {
        for (var i = 0; i < opts.length; i++) {
            if (String(opts[i].value) === String(value)) {
                return i
            }
        }
        return -1
    }

    /** Fill the sheet. original: trip JSON (edit) or null (new). */
    function load(form, originalTrip, linked, asSuggestion) {
        root.original = originalTrip || null
        root.suggestionMode = !!asSuggestion
        root.baseForm = form || Mileage.emptyForm(root.ping, "")
        root.linkedText = linked || ""
        root.serverErrors = ({})
        root.errorText = ""
        var f = root.baseForm
        var d = Mileage.parseDateString(f.date) || new Date()
        dateField.setDate(d)
        purposeCombo.touched = false
        purposeCombo.currentIndex = Math.max(0, indexOfValue(root.purposeOptions, f.purpose))
        vehicleCombo.touched = false
        vehicleCombo.currentIndex = Math.max(0, indexOfValue(root.vehicleOptions, f.vehicle))
        assignedCombo.touched = false
        assignedCombo.currentIndex = Math.max(0, indexOfValue(root.assignedVehicleOptions, f.vehicleId))
        distanceField.text = f.distanceKm === null || f.distanceKm === undefined ? "" : String(f.distanceKm)
        roundTripCheck.checked = f.roundTrip === true
        startField.text = f.start || ""
        destinationField.text = f.destination || ""
        timesCheck.checked = f.withTimes === true
        setTimeField(departureField, f.departure, 8, 0)
        setTimeField(arrivalField, f.arrival, 9, 0)
        commentField.text = f.comment || ""
    }

    function setTimeField(field, text, h, m) {
        var match = /^(\d{1,2}):(\d{2})$/.exec(String(text || ""))
        if (match) {
            field.setTime(Number(match[1]), Number(match[2]))
        } else {
            field.setTime(h, m)
        }
    }

    function currentForm() {
        var f = {}
        for (var k in root.baseForm) {
            f[k] = root.baseForm[k]
        }
        var d = DTF.coerceDate(dateField.selectedDate)
        f.date = d ? Mileage.dateString(d) : ""
        var p = root.purposeOptions[purposeCombo.currentIndex]
        f.purpose = p ? p.value : Mileage.Purpose.BUSINESS
        var v = root.vehicleOptions[vehicleCombo.currentIndex]
        f.vehicle = v ? v.value : Mileage.DEFAULT_VEHICLE
        // The vehicle list may arrive after load(): keep the loaded vehicle unless the user picked one.
        if (assignedCombo.touched) {
            var a = root.assignedVehicleOptions[assignedCombo.currentIndex]
            f.vehicleId = a ? a.value : null
        }
        f.distanceKm = distanceField.text
        f.roundTrip = roundTripCheck.checked
        f.start = startField.text
        f.destination = destinationField.text
        f.withTimes = timesCheck.checked
        f.departure = pad2(departureField.hours) + ":" + pad2(departureField.minutes)
        f.arrival = pad2(arrivalField.hours) + ":" + pad2(arrivalField.minutes)
        f.comment = commentField.text
        return f
    }

    function unlinkTimesheet() {
        var f = {}
        for (var k in root.baseForm) {
            f[k] = root.baseForm[k]
        }
        f.timesheet = null
        root.baseForm = f
        root.linkedText = ""
    }

    function errorFor(field) {
        if (root.serverErrors && root.serverErrors[field]) {
            return String(root.serverErrors[field])
        }
        var code = root.localErrors[field]
        if (!code) {
            return ""
        }
        if (field === "date" && code === "locked") {
            return i18n("This month of the logbook is closed.")
        }
        if (field === "distanceKm" && code === "required") {
            return i18n("Enter the distance.")
        }
        if (field === "distanceKm") {
            return i18n("Enter a distance between 0 and %1 km.", Mileage.MAX_DISTANCE_KM)
        }
        if (field === "arrival" && code === "beforeDeparture") {
            return i18n("Arrival must be after departure.")
        }
        if (field === "comment") {
            return i18n("At most %1 characters.", Mileage.MAX_COMMENT)
        }
        return i18n("Invalid value.")
    }

    readonly property bool fieldsEnabled: configured && !busy

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.bold: true
        text: root.suggestionMode ? i18n("Accept detected trip")
            : (root.editing ? i18n("Edit trip") : i18n("Log trip"))
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        DateField {
            id: dateField
            Kirigami.FormData.label: i18n("Date:")
            Layout.fillWidth: true
            enabled: root.fieldsEnabled && !root.suggestionMode
        }
        QQC2.Label {
            visible: text.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: KanteStyle.negativeTextColor
            text: root.errorFor("date")
        }

        QQC2.ComboBox {
            KanteFieldSkin { control: parent }
            id: purposeCombo
            Kirigami.FormData.label: i18n("Purpose:")
            Layout.fillWidth: true
            enabled: root.fieldsEnabled
            model: root.purposeOptions
            textRole: "label"
            // /meta may arrive after load(): keep the loaded value unless the user picked one.
            property bool touched: false
            onActivated: touched = true
            onModelChanged: {
                if (!touched) {
                    currentIndex = Math.max(0, root.indexOfValue(root.purposeOptions, root.baseForm.purpose))
                }
            }
        }

        QQC2.ComboBox {
            KanteFieldSkin { control: parent }
            id: vehicleCombo
            Kirigami.FormData.label: i18n("Means of travel:")
            Layout.fillWidth: true
            enabled: root.fieldsEnabled
            model: root.vehicleOptions
            textRole: "label"
            // /meta may arrive after load(): keep the loaded value unless the user picked one.
            property bool touched: false
            onActivated: touched = true
            onModelChanged: {
                if (!touched) {
                    currentIndex = Math.max(0, root.indexOfValue(root.vehicleOptions, root.baseForm.vehicle))
                }
            }
        }

        QQC2.ComboBox {
            KanteFieldSkin { control: parent }
            id: assignedCombo
            Kirigami.FormData.label: i18n("Vehicle:")
            Layout.fillWidth: true
            visible: root.vehicles.length > 0 && !root.suggestionMode
            enabled: root.fieldsEnabled
            model: root.assignedVehicleOptions
            textRole: "label"
            property bool touched: false
            onActivated: touched = true
            onModelChanged: {
                if (!touched) {
                    currentIndex = Math.max(0, root.indexOfValue(root.assignedVehicleOptions, root.baseForm.vehicleId))
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Distance (one way):")
            Layout.fillWidth: true
            KanteTextField {
                id: distanceField
                Layout.fillWidth: true
                enabled: root.fieldsEnabled
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: RegularExpressionValidator { regularExpression: /[0-9]{0,5}([.,][0-9]{0,2})?/ }
                placeholderText: {
                    var km = Mileage.commuteKm(root.ping)
                    var p = root.purposeOptions[purposeCombo.currentIndex]
                    return (!root.editing && km !== null && p && p.value === Mileage.Purpose.COMMUTE)
                        ? i18n("%1 (from your profile)", Mileage.formatKm(km)) : ""
                }
                Accessible.name: i18n("Distance in kilometers")
            }
            QQC2.Label {
                text: i18n("km")
            }
        }
        QQC2.Label {
            visible: text.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: KanteStyle.negativeTextColor
            text: root.errorFor("distanceKm")
        }

        QQC2.CheckBox {
            KanteCheckSkin { control: parent }
            id: roundTripCheck
            text: i18n("Round trip (there and back)")
            enabled: root.fieldsEnabled && !root.suggestionMode
        }

        KanteTextField {
            id: startField
            Kirigami.FormData.label: i18n("From:")
            Layout.fillWidth: true
            enabled: root.fieldsEnabled && !root.suggestionMode
            maximumLength: 255
        }

        KanteTextField {
            id: destinationField
            Kirigami.FormData.label: i18n("To:")
            Layout.fillWidth: true
            enabled: root.fieldsEnabled && !root.suggestionMode
            maximumLength: 255
        }

        QQC2.CheckBox {
            KanteCheckSkin { control: parent }
            id: timesCheck
            text: i18n("Departure and arrival times")
            enabled: root.fieldsEnabled && !root.suggestionMode
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Departure / arrival:")
            Layout.fillWidth: true
            visible: timesCheck.checked
            TimeField {
                id: departureField
                Layout.fillWidth: true
                enabled: root.fieldsEnabled && !root.suggestionMode
            }
            QQC2.Label {
                text: "–"
            }
            TimeField {
                id: arrivalField
                Layout.fillWidth: true
                enabled: root.fieldsEnabled && !root.suggestionMode
            }
        }
        QQC2.Label {
            visible: timesCheck.checked && text.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: KanteStyle.negativeTextColor
            text: root.errorFor("arrival") || root.errorFor("departure")
        }

        KanteTextField {
            id: commentField
            Kirigami.FormData.label: i18n("Comment:")
            Layout.fillWidth: true
            enabled: root.fieldsEnabled
            maximumLength: Mileage.MAX_COMMENT
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Time entry:")
            Layout.fillWidth: true
            visible: root.linkedText.length > 0
            QQC2.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.linkedText
            }
            KanteToolButton {
                icon.name: "edit-clear"
                text: i18n("Unlink")
                display: QQC2.AbstractButton.IconOnly
                enabled: root.fieldsEnabled
                onClicked: root.unlinkTimesheet()
                QQC2.ToolTip.text: i18n("Do not link this trip to the time entry")
                QQC2.ToolTip.visible: hovered && !TouchUi.active
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: text.length > 0
        wrapMode: Text.WordWrap
        color: KanteStyle.negativeTextColor
        text: root.errorText
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        KanteButton {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            highlighted: true
            enabled: root.fieldsEnabled && root.connectionOk && root.formValid
            text: root.suggestionMode ? i18n("Accept") : (root.editing ? i18n("Save trip") : i18n("Log trip"))
            icon.name: "document-save"
            onClicked: {
                root.serverErrors = ({})
                root.errorText = ""
                var form = root.currentForm()
                root.saveRequested(Mileage.toApiBody(form, root.original, root.ping),
                                   root.editing ? root.original.id : null, form)
            }
        }

        KanteButton {
            id: deleteButton
            visible: root.canDelete
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            enabled: root.fieldsEnabled && root.connectionOk
            // Two steps instead of a dialog: the sheet lives in the Plasmoid popup and on a phone page.
            property bool armed: false
            text: armed ? i18n("Really delete?") : i18n("Delete")
            icon.name: "edit-delete"
            onClicked: {
                if (!armed) {
                    armed = true
                    return
                }
                armed = false
                root.deleteRequested(root.original.id)
            }
            Connections {
                target: root
                function onOriginalChanged() { deleteButton.armed = false }
            }
        }
    }

    KanteButton {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
        flat: true
        text: i18n("Cancel")
        onClicked: root.cancelled()
    }
}
