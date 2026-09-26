import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/mileage.js" as Mileage
import "shared"
import "Kante"

/**
 * One trip of the kimai-anfahrten plugin: new, edit (original set), linked
 * to a Kimai entry, or a detected trip before accepting it (suggestion set).
 * Pops itself after a successful save and emits saved().
 */
Kirigami.Page {
    id: page
    KantePageTitle { page: page }
    title: page.suggestion ? i18n("Detected trip") : (page.original ? i18n("Edit trip") : i18n("Log trip"))

    property var form: null
    property var original: null
    property string linkedText: ""
    property var suggestion: null
    property bool busy: false

    signal saved()

    function currentUrl() { return TimeTracker.resolveUrl(root.activeProfile) }

    function done(tripJson) {
        page.busy = false
        if (tripJson) {
            root.showPassiveNotification(i18n("Trip saved: %1 km", Mileage.displayKm(Mileage.tripKm(tripJson))))
        }
        page.saved()
        pageStack.pop()
    }

    function failed(error) {
        page.busy = false
        sheet.serverErrors = (error && error.fields) ? error.fields : ({})
        sheet.errorText = (error && error.detail) ? error.detail : ApiErrors.text(error)
    }

    function save(body, tripId, form) {
        if (page.busy) return
        page.busy = true
        var handle = function(r) { if (r.ok) page.done(r.data); else page.failed(r.error) }
        if (page.suggestion) {
            KimaiApi.acceptTripSuggestion(currentUrl(), root.apiToken, page.suggestion.id,
                                          Mileage.acceptBodyFromForm(root.mileagePing, form, page.suggestion), handle)
        } else if (tripId !== null && tripId !== undefined) {
            if (Mileage.isEmptyBody(body)) { page.done(null); return }
            KimaiApi.patchTrip(currentUrl(), root.apiToken, tripId, body, handle)
        } else {
            KimaiApi.createTrip(currentUrl(), root.apiToken, body, handle)
        }
    }

    function remove(tripId) {
        if (page.busy) return
        page.busy = true
        KimaiApi.deleteTrip(currentUrl(), root.apiToken, tripId, function(r) {
            if (r.ok) page.done(null); else page.failed(r.error)
        })
    }

    Component.onCompleted: sheet.load(page.form || Mileage.emptyForm(root.mileagePing, ""), page.original, page.linkedText, !!page.suggestion)

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: pageScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            TripSheet {
                id: sheet
                Layout.fillWidth: true
                busy: page.busy
                configured: root.isConfigured
                connectionOk: root.connectionState !== "error"
                ping: root.mileagePing
                meta: root.mileageMeta
                vehicles: root.mileageVehicles
                onSaveRequested: function(body, tripId, form) { page.save(body, tripId, form) }
                onDeleteRequested: function(tripId) { page.remove(tripId) }
                onCancelled: pageStack.pop()
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing }
        }
    }

    // Pull to refresh (see shared/KantePullToRefresh.qml).
    KantePullToRefresh {
        parent: pageScroll
        anchors.fill: parent
        z: 10
        flickable: pageScroll.contentItem
        busy: false
        onRefreshRequested: root.resolveMileage(true)
    }
}
