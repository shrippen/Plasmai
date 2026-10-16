import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "../code/kimaiApi.js" as KimaiApi
import "../code/timesheetFields.js" as TimesheetFields
import "../code/dateTimeFormat.js" as DTF
import "."
import "Kante"
import "KantePlasma"

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

    // The session layer (Session.qml): data and actions.
    required property QtObject session
    // Widget root (main.qml): view state and navigation only (editors, dialogs, flashes).
    required property var view
    // Popup root: parent for dialogs.
    required property Item popupItem
    // Scroll view the pickers keep their popups inside.
    required property Item pickerScroll

    /** Whether the card should show; the Loader in main.qml follows it. */
    readonly property bool shown: session.connection.configured && !view.showSetupState

    Layout.fillWidth: true
    visible: shown
    implicitHeight: column.implicitHeight + padding * 2 + card.barHeight

    readonly property int padding: Kirigami.Units.largeSpacing
    readonly property string beginClock: {
        var ts = session.timer.active
        var d = ts && ts.begin ? DTF.parseStamp(ts.begin) : null
        return d && !isNaN(d.getTime()) ? d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat) : ""
    }

    KanteCard {
        id: card
        anchors.fill: parent
        barColor: session.timer.tracking ? KanteStyle.accentColor : KanteStyle.frameColor
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: heroCard.padding
        anchors.topMargin: heroCard.padding + card.barHeight
        spacing: Kirigami.Units.smallSpacing

        LoadingRow {
            Layout.fillWidth: true
            visible: !session.timer.loaded && !session.timer.tracking && session.timer.project.length === 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: session.timer.tracking
                      ? (heroCard.beginClock.length > 0 ? i18n("Running since %1", heroCard.beginClock) : i18n("Running"))
                      : i18n("Not tracking")
                font: KanteStyle.labelFont()
                color: KanteStyle.mutedTextColor
                elide: Text.ElideRight
            }

            KantePlasmaToolButton {
                visible: session.timer.tracking && session.trips.canEdit && !!session.timer.active
                enabled: !session.busy && !view.tripBusy
                text: i18n("Log trip")
                icon.name: "mark-location"
                display: QQC2.AbstractButton.IconOnly
                onClicked: view.openTripForTimesheet(session.timer.active)
                PlasmaComponents3.ToolTip.text: i18n("Log a trip for this entry")
                PlasmaComponents3.ToolTip.visible: hovered && !TouchUi.active
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            KantePlasmaToolButton {
                visible: session.timer.tracking
                enabled: !session.busy
                text: i18n("Edit")
                icon.name: "document-edit"
                display: QQC2.AbstractButton.IconOnly
                checked: view.editingActiveEntry
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
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: session.timer.tracking ? KimaiApi.formatDuration(session.timer.elapsedSeconds) : "00:00:00"
                font: KanteStyle.monoFont(KanteStyle.defaultFont.pointSize * 2.6, true)
                color: session.timer.tracking ? KanteStyle.accentTextColor : KanteStyle.tint(KanteStyle.textColor, 0.3)
                fontSizeMode: Text.HorizontalFit
                minimumPointSize: KanteStyle.defaultFont.pointSize * 1.4
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
                visible: session.timer.tracking
                emphasis: KantePlasmaButton.Emphasis.Destructive
                Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                enabled: !session.busy
                text: i18n("Stop")
                icon.name: "media-playback-stop"
                onClicked: view.requestStop()
            }
        }

        // Running: activity as the heading, project and customer below.
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: session.timer.tracking
            text: session.timer.activity
            font: KanteStyle.headingFont(KanteStyle.defaultFont.pointSize * 1.3)
            color: KanteStyle.strongTextColor
            elide: Text.ElideRight
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: session.timer.tracking
            text: session.timer.customer.length > 0
                  ? session.timer.project + " · " + session.timer.customer
                  : session.timer.project
            color: KanteStyle.mutedTextColor
            elide: Text.ElideRight
        }

        // Not tracking: today at a glance.
        EntryDayStrip {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            visible: !session.timer.tracking && view.showSparklineHere
            entries: session.totals.todayEntries
            customersById: session.catalog.customersById
            workDayBegin: view.workDayBegin
            workDayEnd: view.workDayEnd
            latitude: session.settings.latitude
            longitude: session.settings.longitude
            nowTick: view.sparklineNowTick
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
            visible: session.timer.tracking && !view.editingActiveEntry
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
                Layout.fillWidth: true
                Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
                emphasis: KantePlasmaButton.Emphasis.Primary
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
                emphasis: KantePlasmaButton.Emphasis.Primary
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

        // Today · week · what is left of the week (work contract).
        RowLayout {
            Layout.fillWidth: true
            visible: session.timer.tracking || view.showWorkSummaryHere
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                text: i18n("Today %1", DTF.hoursMinutes(session.totals.todayLiveSeconds))
                font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, false)
                color: KanteStyle.mutedTextColor
            }
            PlasmaComponents3.Label {
                text: i18n("Week %1", DTF.hoursMinutes(session.totals.weekLiveSeconds))
                font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, false)
                color: KanteStyle.mutedTextColor
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.Label {
                visible: session.totals.hasWorkContract && session.totals.weekTargetSeconds > 0
                text: session.totals.remainingWeekSeconds >= 0
                      ? i18n("%1 left", DTF.hoursMinutes(session.totals.remainingWeekSeconds))
                      : i18n("%1 over", DTF.hoursMinutes(-session.totals.remainingWeekSeconds))
                font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize, true)
                color: session.totals.remainingWeekSeconds >= 0 ? KanteStyle.positiveTextColor : KanteStyle.neutralTextColor
            }
        }
    }
}
