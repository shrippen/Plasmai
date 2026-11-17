import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/statsData.js" as StatsData
import "shared"
import "Kante"

Kirigami.Page {
    id: page
    readonly property QtObject session: root.session
    KantePageTitle { page: page }
    title: i18n("Statistics")

    // While the page lives the week's entries do not replace the loaded range.
    Component.onCompleted: {
        session.stats.shown = true
        session.stats.open()
    }
    Component.onDestruction: session.stats.shown = false

    /** Pull to refresh: forget the loaded range, fetch it, trips and totals again. */
    function reloadAll() {
        session.stats.forget()
        statsView.ensureRangeForOffsets()
        session.stats.open()
        session.refresh()
    }

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        // The scroll bar sits at the screen edge; the content keeps the page margin.
        anchors.rightMargin: -page.rightPadding
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: col
            width: (pageScroll.availableWidth - page.rightPadding)
            spacing: Kirigami.Units.smallSpacing

            StatsView {
                id: statsView
                Layout.fillWidth: true
                timesheets: session.stats.timesheets
                customersById: session.catalog.customersById
                todayTargetSeconds: session.totals.todayTargetSeconds
                weekTargetSeconds: session.totals.weekEffectiveTargetSeconds
                hasWorkContract: session.totals.hasWorkContract
                workDayBegin: session.settings.workDayBegin
                workDayEnd: session.settings.workDayEnd
                supportsBillableFilter: session.connection.capabilities.billableFilter
                tripSummary: session.stats.trips ? StatsData.tripKmSummary(session.stats.trips, new Date()) : null
                onNeedMoreHistory: function(rangeBegin, rangeEnd) { session.stats.load(rangeBegin, rangeEnd) }
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
        busy: session.stats.loading
        onRefreshRequested: page.reloadAll()
    }
}
