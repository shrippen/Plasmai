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
 * Trips of the kimai-anfahrten plugin (A4): the month's logbook, detected
 * trips (Dawarich) to accept or dismiss, "Log trip" and "Commute today".
 */
Kirigami.Page {
    id: page
    KantePageTitle { page: page }
    title: i18n("Trips")

    property var month: Mileage.addMonths(new Date(), 0)
    property var trips: []
    property var suggestions: []
    property bool loading: false
    property bool busy: false
    readonly property var range: Mileage.monthRange(page.month)
    readonly property var summary: Mileage.summarize(page.trips, range.from, range.to)
    readonly property bool monthLocked: Mileage.isMonthLocked(root.mileagePing, range.from)
    readonly property bool hasDawarich: !!Mileage.profileOf(root.mileagePing).dawarichConfigured
    readonly property var purposeFallback: ({
        "business": i18n("Business trip"),
        "commute": i18n("Commute"),
        "private": i18n("Private")
    })

    function currentUrl() { return TimeTracker.resolveUrl(root.activeProfile) }

    function reload() {
        if (!root.mileageAvailable) return
        page.loading = true
        var r = page.range
        var query = Mileage.hasFeature(root.mileagePing, "dateRange") ? r
            : { year: page.month.getFullYear(), month: page.month.getMonth() + 1 }
        KimaiApi.fetchTrips(currentUrl(), root.apiToken, query, function(res) {
            page.loading = false
            if (res.ok) page.trips = Mileage.sortTrips(res.data)
            else root.showPassiveNotification(i18n("Trips could not be loaded: %1", ApiErrors.text(res.error)))
        })
        if (page.hasDawarich && root.canEditTrips) {
            KimaiApi.fetchTripSuggestions(currentUrl(), root.apiToken, null, function(res) {
                if (res.ok) page.suggestions = res.data
            })
        } else {
            page.suggestions = []
        }
    }

    function stepMonth(delta) {
        page.month = Mileage.addMonths(page.month, delta)
        page.trips = []
        reload()
    }

    function pushEdit(props) {
        var p = pageStack.push(tripEditPageComponent, props)
        if (p) p.saved.connect(page.reload)
    }

    function commuteToday() {
        if (page.busy) return
        if (Mileage.commuteKm(root.mileagePing) === null) {
            // No commute distance in the Kimai profile: let the user enter it.
            var f = Mileage.emptyForm(root.mileagePing, Mileage.dateString(new Date()))
            f.purpose = Mileage.Purpose.COMMUTE
            pushEdit({ form: f })
            return
        }
        page.busy = true
        KimaiApi.createTrip(currentUrl(), root.apiToken, Mileage.commuteBody(Mileage.dateString(new Date())), function(r) {
            page.busy = false
            if (r.ok) {
                root.showPassiveNotification(i18n("Commute logged: %1 km", Mileage.displayKm(Mileage.tripKm(r.data))))
                page.reload()
            } else {
                root.showPassiveNotification((r.error && r.error.detail) || ApiErrors.text(r.error))
            }
        })
    }

    function accept(sg) {
        if (page.busy || !sg) return
        page.busy = true
        KimaiApi.acceptTripSuggestion(currentUrl(), root.apiToken, sg.id, {}, function(r) {
            page.busy = false
            if (!r.ok && !(r.error && r.error.status === 409)) {
                root.showPassiveNotification(i18n("The trip could not be accepted: %1", (r.error && r.error.detail) || ApiErrors.text(r.error)))
                return
            }
            page.reload()
        })
    }

    function dismiss(sg) {
        if (page.busy || !sg) return
        page.busy = true
        KimaiApi.dismissTripSuggestion(currentUrl(), root.apiToken, sg.id, function(r) {
            page.busy = false
            if (!r.ok) {
                root.showPassiveNotification(i18n("The trip could not be dismissed: %1", (r.error && r.error.detail) || ApiErrors.text(r.error)))
                return
            }
            page.suggestions = page.suggestions.filter(function(x) { return x.id !== sg.id })
        })
    }

    actions: [
        Kirigami.Action {
            visible: root.canEditTrips
            icon.name: "list-add"
            text: i18n("Log trip")
            onTriggered: page.pushEdit({ form: Mileage.emptyForm(root.mileagePing, Mileage.dateString(new Date())) })
        },
        Kirigami.Action {
            visible: root.canEditTrips
            icon.name: "mark-location"
            text: i18n("Commute today")
            enabled: !page.busy
            onTriggered: page.commuteToday()
        },
        Kirigami.Action {
            icon.name: "view-refresh"
            text: i18n("Refresh")
            displayHint: Kirigami.DisplayHint.IconOnly
            onTriggered: page.reload()
        }
    ]

    Component.onCompleted: reload()

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: pageScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            KanteHeading {
                Layout.fillWidth: true
                level: 4
                visible: page.suggestions.length > 0
                text: i18n("Detected trips")
            }
            TripSuggestionList {
                Layout.fillWidth: true
                visible: page.suggestions.length > 0
                suggestions: page.suggestions
                busy: page.busy
                canEdit: root.canEditTrips
                meta: root.mileageMeta
                onAcceptRequested: function(sg) { page.accept(sg) }
                onDismissRequested: function(sg) { page.dismiss(sg) }
                onEditRequested: function(sg) { page.pushEdit({ form: Mileage.formFromSuggestion(root.mileagePing, sg), suggestion: sg }) }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                KanteToolButton {
                    icon.name: "go-previous"
                    text: i18n("Previous month")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: page.stepMonth(-1)
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.bold: true
                    text: page.month.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                }
                KanteToolButton {
                    icon.name: "go-next"
                    text: i18n("Next month")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: page.stepMonth(1)
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.8
                text: i18np("%2 km in 1 trip", "%2 km in %1 trips", page.summary.count, Mileage.displayKm(page.summary.km))
                      + (page.monthLocked ? " · " + i18n("month closed") : "")
            }

            QQC2.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: page.loading && page.trips.length === 0
                running: visible
            }

            Kirigami.PlaceholderMessage {
                Layout.fillWidth: true
                visible: !page.loading && page.trips.length === 0
                icon.name: "mark-location"
                text: i18n("No trips this month")
            }

            Repeater {
                model: page.trips
                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    enabled: root.canEditTrips
                    onClicked: page.pushEdit({ form: Mileage.formFromTrip(modelData), original: modelData,
                                               linkedText: modelData.timesheet ? i18n("Time entry #%1", modelData.timesheet) : "" })
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Mileage.routeText(modelData.start, modelData.destination)
                                      || Mileage.labelOf(root.mileageMeta ? root.mileageMeta.purposes : null, modelData.purpose, page.purposeFallback)
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pointSize: KanteStyle.smallFont.pointSize
                                opacity: 0.7
                                text: {
                                    var d = Mileage.parseDateString(modelData.date)
                                    var bits = [d ? d.toLocaleDateString(Qt.locale(), Locale.ShortFormat) : modelData.date,
                                                Mileage.labelOf(root.mileageMeta ? root.mileageMeta.purposes : null, modelData.purpose, page.purposeFallback)]
                                    if (modelData.roundTrip) bits.push(i18n("round trip"))
                                    return bits.join(" · ")
                                }
                            }
                        }
                        QQC2.Label {
                            font.bold: true
                            text: i18n("%1 km", Mileage.displayKm(Mileage.tripKm(modelData)))
                        }
                    }
                }
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
        busy: page.loading
        onRefreshRequested: { root.resolveMileage(true); page.reload() }
    }
}
