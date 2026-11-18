import QtQuick
import "."

/**
 * Connects the trip form to the session, for the widget and the app alike:
 * what the form shows of the trips part, saving and deleting, and the plugin's
 * field errors on the form. The host sets `view`, `session` and `suggestion`
 * (the detected trip the form shows, or null) and says what follows a save.
 */
QtObject {
    id: binding

    property QtObject session: null
    property Item view: null
    property var suggestion: null

    /** The trip was saved (its JSON, null when nothing changed) or deleted (null). */
    signal done(var trip)

    /** Puts a failed answer on the form: the plugin's field errors and the text. */
    function fail(error) {
        if (!binding || !view) {
            return
        }
        view.serverErrors = (error && error.fields) ? error.fields : ({})
        view.errorText = ApiErrors.withServer(error)
    }

    function answered(r) {
        if (!binding) {
            return
        }
        if (!r.ok) {
            fail(r.error)
            return
        }
        done(r.data)
    }

    readonly property list<QtObject> shown: [
        Binding { target: binding.view; property: "configured"; value: binding.session.connection.configured },
        Binding { target: binding.view; property: "ping"; value: binding.session.trips.ping },
        Binding { target: binding.view; property: "meta"; value: binding.session.trips.meta },
        Binding { target: binding.view; property: "vehicles"; value: binding.session.trips.vehicles },
        Binding { target: binding.view; property: "places"; value: binding.session.setup }
    ]

    readonly property Connections sheetSignals: Connections {
        target: binding.view

        function onSaveRequested(body, tripId, form) {
            binding.session.trips.save(body, tripId, form, binding.suggestion, binding.answered)
        }
        function onDeleteRequested(tripId) {
            binding.session.trips.remove(tripId, binding.answered)
        }
    }
}
