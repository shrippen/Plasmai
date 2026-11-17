import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/mileage.js" as Mileage
import "shared"
import "Kante"

/**
 * One trip of the kimai-anfahrten plugin: new, edit (original set), linked
 * to a Kimai entry, or a detected trip before accepting it (suggestion set).
 * Pops itself after a successful save; the lists follow session.trips.changed().
 */
Kirigami.Page {
    id: page
    readonly property QtObject session: root.session
    KantePageTitle { page: page }
    title: page.suggestion ? i18n("Detected trip") : (page.original ? i18n("Edit trip") : i18n("Log trip"))

    property var form: null
    property var original: null
    property string linkedText: ""
    property var suggestion: null
    readonly property bool busy: session.trips.busy

    function done(tripJson) {
        if (tripJson) {
            root.showPassiveNotification(i18n("Trip saved: %1 km", Mileage.displayKm(Mileage.tripKm(tripJson))))
        }
        pageStack.pop()
    }

    function failed(error) {
        sheet.serverErrors = (error && error.fields) ? error.fields : ({})
        sheet.errorText = ApiErrors.withServer(error)
    }

    function save(body, tripId, form) {
        session.trips.save(body, tripId, form, page.suggestion, function(r) {
            // The page is gone: nothing to close or show.
            if (!page) { return }
            if (r.ok) page.done(r.data); else page.failed(r.error)
        })
    }

    function remove(tripId) {
        session.trips.remove(tripId, function(r) {
            // The page is gone: nothing to close or show.
            if (!page) { return }
            if (r.ok) page.done(null); else page.failed(r.error)
        })
    }

    Component.onCompleted: sheet.load(page.form || Mileage.emptyForm(session.trips.ping, ""), page.original, page.linkedText, !!page.suggestion)

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        // The scroll bar sits at the screen edge; the content keeps the page margin.
        anchors.rightMargin: -page.rightPadding
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: (pageScroll.availableWidth - page.rightPadding)
            spacing: Kirigami.Units.smallSpacing

            TripSheet {
                id: sheet
                Layout.fillWidth: true
                busy: page.busy
                places: session.setup
                configured: session.connection.configured
                connectionOk: session.connection.state !== "error"
                ping: session.trips.ping
                meta: session.trips.meta
                vehicles: session.trips.vehicles
                onSaveRequested: function(body, tripId, form) { page.save(body, tripId, form) }
                onDeleteRequested: function(tripId) { page.remove(tripId) }
                onCancelled: pageStack.pop()
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing }
        }
    }

}
