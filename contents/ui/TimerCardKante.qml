import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "../code/kimaiApi.js" as KimaiApi
import "../code/timesheetFields.js" as TimesheetFields
import "../code/dateTimeFormat.js" as DTF
import "."

/**
 * Timer card of the main view in the Kante style (see TimerCard.qml for
 * System). Same state and actions, other layout:
 *
 *   ┌─────────────────────────────────────╮  accent bar, cut corner
 *   │ RUNNING SINCE 07:42        [⌖] [✎] │
 *   │ 01:28:16                   [STOP]  │  mono, accent
 *   │ Maintenance                         │  heading
 *   │ Internal · Server/Services          │
 *   │ [description…]                      │
 *   │ Today 6:12  Week 31:10     left 8:50│
 *   └─────────────────────────────────────┘
 *
 * Not tracking: dimmed 00:00:00, today's strip and a Continue button.
 */
Item {
    id: heroCard

    // Widget root (main.qml): state and actions.
    required property var widget
    // Popup root: parent for dialogs.
    required property Item popupItem
    // Scroll view the pickers keep their popups inside.
    required property Item pickerScroll

    /** Whether the card should show; the Loader in main.qml follows it. */
    readonly property bool shown: widget.isConfigured && !widget.showSetupState

    Layout.fillWidth: true
    visible: shown
    implicitHeight: column.implicitHeight + padding * 2 + card.barHeight

    readonly property int padding: Kirigami.Units.largeSpacing
    readonly property string beginClock: {
        var ts = widget.activeTimesheet
        var d = ts && ts.begin ? new Date(ts.begin) : null
        return d && !isNaN(d.getTime()) ? d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat) : ""
    }

    KanteCard {
        id: card
        anchors.fill: parent
        barColor: widget.isTracking ? Style.accentColor : Style.frameColor
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: heroCard.padding
        anchors.topMargin: heroCard.padding + card.barHeight
        spacing: Kirigami.Units.smallSpacing

        LoadingRow {
            Layout.fillWidth: true
            visible: widget.loadingActive && !widget.isTracking && widget.currentProject.length === 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: widget.isTracking
                      ? (heroCard.beginClock.length > 0 ? i18n("Running since %1", heroCard.beginClock) : i18n("Running"))
                      : i18n("Not tracking")
                font: Style.labelFont()
                color: Style.mutedTextColor
                elide: Text.ElideRight
            }

            PToolButton {
                visible: widget.isTracking && widget.canEditTrips && !!widget.activeTimesheet
                enabled: !widget.isBusy && !widget.tripBusy
                text: i18n("Log trip")
                icon.name: "mark-location"
                display: QQC2.AbstractButton.IconOnly
                onClicked: widget.openTripForTimesheet(widget.activeTimesheet)
                PlasmaComponents3.ToolTip.text: i18n("Log a trip for this entry")
                PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PToolButton {
                visible: widget.isTracking
                enabled: !widget.isBusy
                text: i18n("Edit")
                icon.name: "document-edit"
                display: QQC2.AbstractButton.IconOnly
                checked: widget.editingActiveEntry
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
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: widget.isTracking ? KimaiApi.formatDuration(widget.elapsedSeconds) : "00:00:00"
                font: Style.monoFont(Style.defaultFont.pointSize * 2.6, true)
                color: widget.isTracking ? Style.accentTextColor : Style.tint(Style.textColor, 0.3)
                fontSizeMode: Text.HorizontalFit
                minimumPointSize: Style.defaultFont.pointSize * 1.4
            }

            PButton {
                visible: widget.isTracking
                emphasis: PButton.Emphasis.Destructive
                Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                enabled: !widget.isBusy
                text: i18n("Stop")
                icon.name: "media-playback-stop"
                onClicked: widget.requestStop()
            }
        }

        // Running: activity as the heading, project and customer below.
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: widget.isTracking
            text: widget.currentActivity
            font: Style.headingFont(Style.defaultFont.pointSize * 1.3)
            color: Style.strongTextColor
            elide: Text.ElideRight
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: widget.isTracking
            text: widget.currentCustomer.length > 0
                  ? widget.currentProject + " · " + widget.currentCustomer
                  : widget.currentProject
            color: Style.mutedTextColor
            elide: Text.ElideRight
        }

        // Not tracking: today at a glance.
        KanteDayStrip {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            visible: !widget.isTracking && widget.showSparklineHere
            entries: widget.todayTimesheets
            customersById: widget.customersById
            workDayBegin: widget.workDayBegin
            workDayEnd: widget.workDayEnd
            nowTick: widget.sparklineNowTick
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
            visible: widget.isTracking && !widget.editingActiveEntry
        }

        PButton {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            emphasis: PButton.Emphasis.Primary
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
            emphasis: PButton.Emphasis.Primary
            visible: widget.showContinueHere && !widget.isTracking && !widget.lastRecent && widget.hasLastUsed
            enabled: widget.isConfigured && !widget.isBusy && widget.connectionState !== "error"
            text: i18n("Start · %1 · %2",
                       Plasmoid.configuration.lastUsedProjectName || "",
                       Plasmoid.configuration.lastUsedActivityName || "")
            icon.name: "media-playback-start"
            onClicked: widget.startLastUsed()
        }

        // Today · week · what is left of the week (work contract).
        RowLayout {
            Layout.fillWidth: true
            visible: widget.isTracking || widget.showWorkSummaryHere
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                text: i18n("Today %1", DTF.hoursMinutes(widget.todayLiveSeconds))
                font: Style.monoFont(Style.smallFont.pointSize, false)
                color: Style.mutedTextColor
            }
            PlasmaComponents3.Label {
                text: i18n("Week %1", DTF.hoursMinutes(widget.weekLiveSeconds))
                font: Style.monoFont(Style.smallFont.pointSize, false)
                color: Style.mutedTextColor
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.Label {
                visible: widget.hasWorkContract && widget.weekTargetSeconds > 0
                text: widget.remainingWeekSeconds >= 0
                      ? i18n("%1 left", DTF.hoursMinutes(widget.remainingWeekSeconds))
                      : i18n("%1 over", DTF.hoursMinutes(-widget.remainingWeekSeconds))
                font: Style.monoFont(Style.smallFont.pointSize, true)
                color: widget.remainingWeekSeconds >= 0 ? Style.positiveTextColor : Style.neutralTextColor
            }
        }
    }
}
