import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "../code/kimaiApi.js" as KimaiApi
import "../code/timesheetFields.js" as TimesheetFields
import "."
import "Kante"
import "KantePlasma"

/**
 * Timer card of the main view: running entry (timer, edit, stop, description)
 * or Continue / Start last used, day sparkline and work summary.
 * Data and actions come from the session, view state from the widget root.
 */
Rectangle {
    id: heroCard

    // The session layer (Session.qml): data and actions.
    required property QtObject session
    // Widget root (main.qml): view state and navigation only (editors, dialogs, flashes).
    required property var view
    // Popup root: parent for dialogs, holds the sparkline for cutout refreshes.
    required property Item popupItem
    // Scroll view the pickers keep their popups inside.
    required property Item pickerScroll

    /** Whether the card should show; the Loader in main.qml follows it. */
    readonly property bool shown: session.connection.configured && !view.showSetupState

    Layout.fillWidth: true
    visible: shown
    radius: 6
    color: session.timer.tracking
           ? KanteStyle.tint(KanteStyle.positiveTextColor, 0.08)
           : KanteStyle.tint(KanteStyle.textColor, 0.04)
    border.width: 1
    border.color: session.timer.tracking
                  ? KanteStyle.tint(KanteStyle.positiveTextColor, 0.28)
                  : KanteStyle.tint(KanteStyle.textColor, 0.12)
    implicitHeight: heroColumn.implicitHeight + Kirigami.Units.smallSpacing * 2

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.topMargin: Math.max(2, Math.round(Kirigami.Units.smallSpacing * 0.35))
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            id: heroColumn
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            LoadingRow {
                Layout.fillWidth: true
                visible: !session.timer.loaded && !session.timer.tracking && session.timer.project.length === 0
            }

            RowLayout {
                id: trackingHeader
                Layout.fillWidth: true
                visible: session.timer.tracking
                spacing: Kirigami.Units.smallSpacing
                z: 3
                onWidthChanged: daySparkline.scheduleHeaderCutouts()
                onHeightChanged: daySparkline.scheduleHeaderCutouts()
                onVisibleChanged: daySparkline.scheduleHeaderCutouts()

                PlasmaComponents3.Label {
                    id: elapsedLabel
                    Layout.alignment: Qt.AlignVCenter
                    text: KimaiApi.formatDuration(session.timer.elapsedSeconds)
                    font.family: KanteStyle.monoFamily
                    font.pointSize: KanteStyle.defaultFont.pointSize + 6
                    font.bold: true
                    color: KanteStyle.positiveTextColor
                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                }

                Item { Layout.fillWidth: true }

                KantePlasmaToolButton {
                    id: tripHeaderButton
                    visible: session.trips.canEdit && !!session.timer.active
                    enabled: !session.busy && !view.tripBusy
                    text: i18n("Log trip")
                    icon.name: "mark-location"
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: view.openTripForTimesheet(session.timer.active)
                    PlasmaComponents3.ToolTip.text: i18n("Log a trip for this entry")
                    PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                }

                KantePlasmaToolButton {
                    id: editHeaderButton
                    enabled: !session.busy
                    text: i18n("Edit")
                    icon.name: "document-edit"
                    display: QQC2.AbstractButton.IconOnly
                    down: view.editingActiveEntry
                    onClicked: {
                        if (view.editingActiveEntry) {
                            view.closeActiveEdit()
                        } else {
                            view.openActiveEdit()
                        }
                    }
                    PlasmaComponents3.ToolTip.text: i18n("Edit start, project, and activity")
                    PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                }

                KantePlasmaButton {
                    visible: session.timer.tracking && view.showNewActivityHere && !view.showNewActivityForm
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                    enabled: session.connection.configured && !session.busy && view.connectionState !== "error"
                    text: i18n("Switch to another activity…")
                    icon.name: "media-playback-start"
                    onClicked: view.showNewActivityForm = true
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                }

                KantePlasmaButton {
                    id: stopHeaderButton
                    Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                    enabled: !session.busy
                    text: i18n("Stop")
                    icon.name: "media-playback-stop"
                    onClicked: view.requestStop()
                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: session.timer.loaded && !session.timer.tracking
                text: i18n("Not tracking")
                font.bold: true
                opacity: 0.85
            }

            DaySparkline {
                id: daySparkline
                Layout.fillWidth: true
                // Pull sky arcs up under the timer / customer row
                Layout.topMargin: {
                    if (!(visible && session.timer.tracking && trackingHeader.visible
                          && session.settings.showSparklineArcs)) {
                        return 1
                    }
                    return -Math.round(trackingHeader.height * 0.984)
                }
                Layout.bottomMargin: 0
                z: 1
                visible: session.connection.configured && view.showSparklineHere
                entries: session.totals.todayEntries
                targetSeconds: session.totals.todayTargetSeconds
                workDayBegin: view.workDayBegin
                workDayEnd: view.workDayEnd
                latitude: session.settings.latitude
                longitude: session.settings.longitude
                nowTick: view.sparklineNowTick
                showArcs: session.settings.showSparklineArcs
                flyoutOpen: view.expanded
                headerMaskItems: [elapsedLabel, editHeaderButton, stopHeaderButton]
                Component.onCompleted: {
                    popupItem.sparklineItem = daySparkline
                    scheduleHeaderCutouts()
                }
                Component.onDestruction: {
                    if (popupItem.sparklineItem === daySparkline) {
                        popupItem.sparklineItem = null
                    }
                }
                onWidthChanged: scheduleHeaderCutouts()
                onHeightChanged: scheduleHeaderCutouts()
                onVisibleChanged: scheduleHeaderCutouts()
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: session.timer.tracking && session.timer.customer.length > 0
                text: session.timer.customer
                elide: Text.ElideRight
                opacity: 0.85
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: session.timer.tracking && heroColumn.width >= Kirigami.Units.gridUnit * 16
                text: session.timer.project + " · " + session.timer.activity
                elide: Text.ElideRight
                font.bold: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: session.timer.tracking && heroColumn.width < Kirigami.Units.gridUnit * 16
                spacing: 0
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: session.timer.project
                    elide: Text.ElideRight
                    font.bold: true
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: session.timer.activity
                    elide: Text.ElideRight
                    opacity: 0.85
                }
            }

            ColumnLayout {
                id: workSummaryBlock
                Layout.fillWidth: true
                visible: session.timer.tracking || view.showWorkSummaryHere
                spacing: 1

                // Edit/Stop now live in trackingHeader beside the timer, so this
                // block is just the stats — no more width-dependent placement.
                RowLayout {
                    Layout.fillWidth: true
                    visible: view.showWorkSummaryHere
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: i18n("Today %1", KimaiApi.formatDurationShort(session.totals.todayLiveSeconds))
                            + " · "
                            + i18n("Week %1", KimaiApi.formatDurationShort(session.totals.weekLiveSeconds))
                        font.pointSize: KanteStyle.smallFont.pointSize
                        opacity: 0.8
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: view.showWorkSummaryHere && session.totals.hasWorkContract
                             && (session.totals.todayTargetSeconds > 0 || session.totals.weekTargetSeconds > 0)
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: session.totals.todayTargetSeconds > 0 || session.totals.weekTargetSeconds > 0
                        text: {
                            var bits = []
                            if (session.totals.todayTargetSeconds > 0) {
                                bits.push(view.remainingTodayText())
                            }
                            if (session.totals.weekTargetSeconds > 0) {
                                bits.push(view.remainingWeekText())
                            }
                            return bits.join(" · ")
                        }
                        font.pointSize: KanteStyle.smallFont.pointSize
                        opacity: 0.75
                        elide: Text.ElideRight
                        color: (session.totals.remainingTodaySeconds < 0 || session.totals.remainingWeekSeconds < 0)
                               ? KanteStyle.neutralTextColor
                               : KanteStyle.textColor
                    }
                }
            }

            ActiveEditView {
                id: activeEditView
                Component.onCompleted: view.activeEditViewRef = activeEditView
                Component.onDestruction: {
                    if (view.activeEditViewRef === activeEditView) {
                        view.activeEditViewRef = null
                    }
                }
                Layout.fillWidth: true
                visible: session.timer.tracking && view.editingActiveEntry
                timesheet: session.timer.active
                elapsedSeconds: session.timer.elapsedSeconds
                previousTimesheet: TimesheetFields.previousStoppedTimesheet(
                    session.recent.list, session.totals.todayEntries, session.timer.active)
                overlapGuardEnabled: session.settings.confirmStartBeforePreviousEnd
                dialogParent: popupItem
                projectPickerModel: session.catalog.projectPickerModel
                activityPickerModel: view.activityPickerModel
                activitySectionTitles: view.activitySectionTitles
                pickerOpenBelow: view.pickerOpenBelow
                pickerViewport: pickerScroll
                busy: session.busy
                configured: session.connection.configured
                connectionOk: view.connectionState !== "error"
                supportsBillableEdit: session.connection.capabilities.billableEdit
    supportsTags: session.connection.capabilities.tags
    tagSource: session.entries
    showCreateActions: session.entries.canCreate
    onAboutToOpenPicker: function(projectField, activityField) {
        view.updatePickerOpenDirection(projectField, activityField)
    }
    onProjectChosen: function(projectId) {
        view.loadActivitiesForProject(projectId)
    }
    onSaveRequested: function(projectId, activityId, beginText, billable, tags) {
        view.saveActiveEdit(projectId, activityId, beginText, billable, tags)
    }
                onCancelled: view.closeActiveEdit()
                onCreateProjectRequested: view.openCreateEntity("project")
                onCreateActivityRequested: view.openCreateEntity("activity")
            }

            DescriptionField {
                session: heroCard.session
                view: heroCard.view
                Layout.fillWidth: true
                visible: session.timer.tracking
            }

            // Continue, and the generic start right beside it (never scrolled to).
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                id: continueRow
                // Conditions, not the children's visible: those read false while the row is hidden.
                readonly property bool continueShown: view.showContinueHere && !session.timer.tracking && !!session.recent.last
                readonly property bool lastUsedShown: view.showContinueHere && !session.timer.tracking && !session.recent.last && session.timer.hasLastUsed
                readonly property bool startShown: view.showNewActivityHere && session.connection.configured && !view.showNewActivityForm
                visible: !session.timer.tracking && (continueShown || lastUsedShown || startShown)

                KantePlasmaButton {
                    id: continueButton
                    emphasis: KantePlasmaButton.Emphasis.Primary
                    Layout.fillWidth: true
                    Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                    visible: view.showContinueHere && !session.timer.tracking && session.recent.last
                    enabled: session.connection.configured && !session.busy && view.connectionState !== "error"
                    text: i18n("Continue · %1 · %2",
                               KimaiApi.displayProjectName(session.recent.last, session.catalog.projects),
                               KimaiApi.displayActivityName(session.recent.last, session.catalog.activities, session.catalog.activitiesByProject))
                    icon.name: "media-playback-start"
                    onClicked: view.continueLastActivity()
                }

                KantePlasmaButton {
                    id: lastUsedButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                    visible: view.showContinueHere && !session.timer.tracking && !session.recent.last && session.timer.hasLastUsed
                    enabled: session.connection.configured && !session.busy && view.connectionState !== "error"
                    text: i18n("Start · %1 · %2",
                               session.settings.lastUsedProjectName || "",
                               session.settings.lastUsedActivityName || "")
                    icon.name: "media-playback-start"
                    onClicked: session.timer.startLastUsed()
                }
                KantePlasmaButton {
                    id: startOtherButton
                    visible: view.showNewActivityHere && session.connection.configured && !view.showNewActivityForm
                    readonly property bool beside: continueRow.continueShown || continueRow.lastUsedShown
                    // Icon only beside Continue, so Continue keeps room for what it continues.
                    display: beside ? QQC2.AbstractButton.IconOnly : QQC2.AbstractButton.TextBesideIcon
                    Layout.fillWidth: !beside
                    Layout.fillHeight: beside
            Layout.preferredWidth: beside ? height : implicitWidth
                    Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                    enabled: session.connection.configured && !session.busy && view.connectionState !== "error"
                    text: i18n("Start something else…")
                    icon.name: "media-playback-start"
                    onClicked: view.showNewActivityForm = true
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                }
            }
        }
    }
}
