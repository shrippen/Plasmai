import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Shapes
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "../code/kimaiApi.js" as KimaiApi
import "../code/timesheetFields.js" as TimesheetFields
import "."

/**
 * Timer card of the main view: running entry (timer, edit, stop, description)
 * or Continue / Start last used, day sparkline and work summary.
 * State and actions live in the widget root (main.qml); this file lays them out.
 */
Rectangle {
    id: heroCard

    // Widget root (main.qml): state and actions.
    required property var widget
    // Popup root: parent for dialogs, holds the sparkline for cutout refreshes.
    required property Item popupItem
    // Scroll view the pickers keep their popups inside.
    required property Item pickerScroll

    /** Whether the card should show; the Loader in main.qml follows it. */
    readonly property bool shown: widget.isConfigured && !widget.showSetupState

    Layout.fillWidth: true
    visible: shown
    radius: 6
    color: widget.isTracking
           ? Qt.rgba(Style.positiveTextColor.r,
                     Style.positiveTextColor.g,
                     Style.positiveTextColor.b, 0.08)
           : Qt.rgba(Style.textColor.r,
                     Style.textColor.g,
                     Style.textColor.b, 0.04)
    border.width: 1
    border.color: widget.isTracking
                  ? Qt.rgba(Style.positiveTextColor.r,
                            Style.positiveTextColor.g,
                            Style.positiveTextColor.b, 0.28)
                  : Qt.rgba(Style.textColor.r,
                            Style.textColor.g,
                            Style.textColor.b, 0.12)
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
                visible: widget.loadingActive && !widget.isTracking && widget.currentProject.length === 0
            }

            RowLayout {
                id: trackingHeader
                Layout.fillWidth: true
                visible: widget.isTracking
                spacing: Kirigami.Units.smallSpacing
                z: 3
                onWidthChanged: daySparkline.scheduleHeaderCutouts()
                onHeightChanged: daySparkline.scheduleHeaderCutouts()
                onVisibleChanged: daySparkline.scheduleHeaderCutouts()

                PlasmaComponents3.Label {
                    id: elapsedLabel
                    Layout.alignment: Qt.AlignVCenter
                    text: KimaiApi.formatDuration(widget.elapsedSeconds)
                    font.family: Style.monoFamily
                    font.pointSize: Style.defaultFont.pointSize + 6
                    font.bold: true
                    color: Style.positiveTextColor
                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                }

                Item { Layout.fillWidth: true }

                PToolButton {
                    id: tripHeaderButton
                    visible: widget.canEditTrips && !!widget.activeTimesheet
                    enabled: !widget.isBusy && !widget.tripBusy
                    text: i18n("Log trip")
                    icon.name: "mark-location"
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: widget.openTripForTimesheet(widget.activeTimesheet)
                    PlasmaComponents3.ToolTip.text: i18n("Log a trip for this entry")
                    PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                }

                PToolButton {
                    id: editHeaderButton
                    enabled: !widget.isBusy
                    text: i18n("Edit")
                    icon.name: "document-edit"
                    display: QQC2.AbstractButton.IconOnly
                    down: widget.editingActiveEntry
                    onClicked: {
                        if (widget.editingActiveEntry) {
                            widget.closeActiveEdit()
                        } else {
                            widget.openActiveEdit()
                        }
                    }
                    PlasmaComponents3.ToolTip.text: i18n("Edit start, project, and activity")
                    PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                }

                PButton {
                    id: stopHeaderButton
                    Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                    enabled: !widget.isBusy
                    text: i18n("Stop")
                    icon.name: "media-playback-stop"
                    onClicked: widget.requestStop()
                    onWidthChanged: daySparkline.scheduleHeaderCutouts()
                    onHeightChanged: daySparkline.scheduleHeaderCutouts()
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: !widget.loadingActive && !widget.isTracking
                text: i18n("Not tracking")
                font.bold: true
                opacity: 0.85
            }

            DaySparkline {
                id: daySparkline
                Layout.fillWidth: true
                // Pull sky arcs up under the timer / customer row
                Layout.topMargin: {
                    if (!(visible && widget.isTracking && trackingHeader.visible
                          && Plasmoid.configuration.showSparklineArcs)) {
                        return 1
                    }
                    return -Math.round(trackingHeader.height * 0.984)
                }
                Layout.bottomMargin: 0
                z: 1
                visible: widget.isConfigured && widget.showSparklineHere
                entries: widget.todayTimesheets
                targetSeconds: widget.todayTargetSeconds
                workDayBegin: widget.workDayBegin
                workDayEnd: widget.workDayEnd
                latitude: Plasmoid.configuration.latitude
                longitude: Plasmoid.configuration.longitude
                nowTick: widget.sparklineNowTick
                showArcs: Plasmoid.configuration.showSparklineArcs
                flyoutOpen: widget.expanded
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
                visible: widget.isTracking && widget.currentCustomer.length > 0
                text: widget.currentCustomer
                elide: Text.ElideRight
                opacity: 0.85
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: widget.isTracking && heroColumn.width >= Kirigami.Units.gridUnit * 16
                text: widget.currentProject + " · " + widget.currentActivity
                elide: Text.ElideRight
                font.bold: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: widget.isTracking && heroColumn.width < Kirigami.Units.gridUnit * 16
                spacing: 0
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: widget.currentProject
                    elide: Text.ElideRight
                    font.bold: true
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: widget.currentActivity
                    elide: Text.ElideRight
                    opacity: 0.85
                }
            }

            ColumnLayout {
                id: workSummaryBlock
                Layout.fillWidth: true
                visible: widget.isTracking || widget.showWorkSummaryHere
                spacing: 1

                // Edit/Stop now live in trackingHeader beside the timer, so this
                // block is just the stats — no more width-dependent placement.
                RowLayout {
                    Layout.fillWidth: true
                    visible: widget.showWorkSummaryHere
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: i18n("Today %1", KimaiApi.formatDurationShort(widget.todayLiveSeconds))
                            + " · "
                            + i18n("Week %1", KimaiApi.formatDurationShort(widget.weekLiveSeconds))
                        font.pointSize: Style.smallFont.pointSize
                        opacity: 0.8
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: widget.showWorkSummaryHere && widget.hasWorkContract
                             && (widget.todayTargetSeconds > 0 || widget.weekTargetSeconds > 0)
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: widget.todayTargetSeconds > 0 || widget.weekTargetSeconds > 0
                        text: {
                            var bits = []
                            if (widget.todayTargetSeconds > 0) {
                                bits.push(widget.remainingTodayText())
                            }
                            if (widget.weekTargetSeconds > 0) {
                                bits.push(widget.remainingWeekText())
                            }
                            return bits.join(" · ")
                        }
                        font.pointSize: Style.smallFont.pointSize
                        opacity: 0.75
                        elide: Text.ElideRight
                        color: (widget.remainingTodaySeconds < 0 || widget.remainingWeekSeconds < 0)
                               ? Style.neutralTextColor
                               : Style.textColor
                    }
                }
            }

            ActiveEditView {
                id: activeEditView
                Component.onCompleted: widget.activeEditViewRef = activeEditView
                Component.onDestruction: {
                    if (widget.activeEditViewRef === activeEditView) {
                        widget.activeEditViewRef = null
                    }
                }
                Layout.fillWidth: true
                visible: widget.isTracking && widget.editingActiveEntry
                timesheet: widget.activeTimesheet
                elapsedSeconds: widget.elapsedSeconds
                previousTimesheet: TimesheetFields.previousStoppedTimesheet(
                    widget.recentTimesheets, widget.todayTimesheets, widget.activeTimesheet)
                overlapGuardEnabled: Plasmoid.configuration.confirmStartBeforePreviousEnd
                dialogParent: popupItem
                projectPickerModel: widget.projectPickerModel
                activityPickerModel: widget.activityPickerModel
                activitySectionTitles: widget.activitySectionTitles
                pickerOpenBelow: widget.pickerOpenBelow
                pickerViewport: pickerScroll
                busy: widget.isBusy
                configured: widget.isConfigured
                connectionOk: widget.connectionState !== "error"
                supportsBillableEdit: widget.providerCapabilities.billableEdit
    supportsTags: widget.providerCapabilities.tags
    tagLookupUrl: widget.kimaiUrl
    tagLookupToken: widget.apiToken
    showCreateActions: widget.providerCapabilities.createEntities
    onAboutToOpenPicker: function(projectField, activityField) {
        widget.updatePickerOpenDirection(projectField, activityField)
    }
    onProjectChosen: function(projectId) {
        widget.loadActivitiesForProject(projectId)
    }
    onSaveRequested: function(projectId, activityId, beginText, billable, tags) {
        widget.saveActiveEdit(projectId, activityId, beginText, billable, tags)
    }
                onCancelled: widget.closeActiveEdit()
                onCreateProjectRequested: widget.openCreateEntity("project")
                onCreateActivityRequested: widget.openCreateEntity("activity")
            }

            DescriptionField {
                widget: heroCard.widget
                Layout.fillWidth: true
                visible: widget.isTracking
            }

            PButton {
                emphasis: PButton.Emphasis.Primary
                Layout.fillWidth: true
                Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                visible: widget.showContinueHere && !widget.isTracking && widget.lastRecent
                enabled: widget.isConfigured && !widget.isBusy && widget.connectionState !== "error"
                text: i18n("Continue · %1 · %2",
                           KimaiApi.displayProjectName(widget.lastRecent, widget.projects),
                           KimaiApi.displayActivityName(widget.lastRecent, widget.allActivities, widget.activitiesByProject))
                icon.name: "media-playback-start"
                onClicked: widget.continueLastActivity()
            }

            PButton {
                Layout.fillWidth: true
                Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                visible: widget.showContinueHere && !widget.isTracking && !widget.lastRecent && widget.hasLastUsed
                enabled: widget.isConfigured && !widget.isBusy && widget.connectionState !== "error"
                text: i18n("Start · %1 · %2",
                           Plasmoid.configuration.lastUsedProjectName || "",
                           Plasmoid.configuration.lastUsedActivityName || "")
                icon.name: "media-playback-start"
                onClicked: widget.startLastUsed()
            }
        }
    }
}
