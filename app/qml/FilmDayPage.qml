import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/dateTimeFormat.js" as DTF
import "shared"
import "Kante"

Kirigami.Page {
    id: page
    readonly property QtObject session: root.session
    KantePageTitle { page: page }
    title: i18n("Film day")

    FilmDayBinding {
        id: binding
        session: page.session
        view: filmDayView
        onProblem: function(text) { root.showPassiveNotification(text) }
        onFailed: function(error) { root.showPassiveNotification(ApiErrors.withServer(error)) }
        onNoteFailed: function(error) {
            root.reportWriteError({ ok: false, error: error }, i18n("Could not save the entry"))
        }
    }

    Component.onCompleted: {
        if (session.catalog.projectPickerModel.length === 0) {
            session.refresh()
        }
        binding.open(Session.Probe.Cached)
    }

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

            FilmDayView {
                id: filmDayView
                Layout.fillWidth: true
                busy: session.filmDay.loading || session.filmDay.saving
                connectionOk: session.connection.state !== "error"
                onProjectChosen: function(projectId) {
                    session.catalog.loadActivities(projectId, function(model) {
                        if (!page) { return }
                        filmDayView.activityPickerModel = model
                    })
                }
                elapsedSeconds: session.timer.elapsedSeconds
                onRunningBeginEdited: function(beginText) {
                    session.timer.patchActive({ begin: DTF.localDateTimeString(DTF.parseStamp(beginText)) })
                }
                onTripRequested: root.openTripForTimesheet(session.filmDay.dayTimesheet)
                onCancelled: pageStack.pop()
                onCreateProjectRequested: { createEntityDialog.customers = session.catalog.customers; createEntityDialog.resetForMode("project"); createEntityDialog.open() }
                onCreateActivityRequested: {
                    createEntityDialog.selectedProjectId = filmDayView.projectCombo.currentItem ? filmDayView.projectCombo.currentItem.value.id : null
                    createEntityDialog.selectedProjectName = filmDayView.projectCombo.currentItem ? filmDayView.projectCombo.currentItem.value.name : ""
                    createEntityDialog.resetForMode("activity"); createEntityDialog.open()
                }
            }
        }
    }

    // The film day follows the main page's timer (Start, Stop, a switch elsewhere).
    Connections {
        target: session.timer
        function onTrackingChanged() { binding.reload() }
    }

    // Leaving the page or the app must not drop a note still being typed: the
    // save starts right away (the request outlives the page).
    Component.onDestruction: filmDayView.flushPending()
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                filmDayView.flushPending()
            }
        }
    }

    CreateEntityDialog {
        id: createEntityDialog
        onSubmitted: function(mode, payload) {
            session.entries.createEntity(mode, payload)
        }
    }

    // Pull to refresh (see shared/KantePullToRefresh.qml).
    KantePullToRefresh {
        parent: pageScroll
        anchors.fill: parent
        z: 10
        flickable: pageScroll.contentItem
        busy: session.filmDay.loading
        onRefreshRequested: binding.open(Session.Probe.Fresh)
    }
}
