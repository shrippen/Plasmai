import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "shared"

Kirigami.Page {
    id: page
    title: i18n("Statistics")

    property var timesheets: []
    property bool loading: false
    property var _rangeBeginMs: 0
    property var _rangeEndMs: 0

    function loadRange(rangeBegin, rangeEnd) {
        if (!root.apiToken) return
        var bMs = rangeBegin.getTime(), eMs = rangeEnd.getTime()
        if (_rangeBeginMs && _rangeEndMs && bMs >= _rangeBeginMs && eMs <= _rangeEndMs && timesheets.length > 0) return
        loading = true
        var url = TimeTracker.resolveUrl(root.activeProfile)
        root.tracker.fetchTimesheetsRange(url, root.apiToken, rangeBegin, rangeEnd, function(r) {
            loading = false
            if (r.ok) {
                timesheets = KimaiApi.hydrateTimesheets(r.data || [], root.projects, root.activityCatalog(), root.activitiesByProject)
                _rangeBeginMs = bMs; _rangeEndMs = eMs
            }
        })
    }

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: col
            width: pageScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            StatsView {
                id: statsView
                Layout.fillWidth: true
                timesheets: page.timesheets
                customersById: root.customersById
                todayTargetSeconds: root.todayTargetSeconds
                weekTargetSeconds: root.weekTargetSeconds
                hasWorkContract: root.hasWorkContract
                workDayBegin: root.workDayBegin
                workDayEnd: root.workDayEnd
                supportsBillableFilter: root.providerCapabilities.billableFilter
                onNeedMoreHistory: function(rangeBegin, rangeEnd) { page.loadRange(rangeBegin, rangeEnd) }
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing }
        }
    }
}
