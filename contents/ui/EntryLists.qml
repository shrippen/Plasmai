import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "../code/kimaiApi.js" as KimaiApi
import "../code/favorites.js" as Favorites
import "../code/mileage.js" as Mileage
import "../code/dateTimeFormat.js" as DTF
import "."
import "Kante"
import "KantePlasma"

/**
 * List part of the main view: favorites, detected trips, recent entries
 * and the start / switch form.
 * State and actions live in the widget root (main.qml); this file lays them out.
 */
ColumnLayout {
    id: listSection

    // Widget root (main.qml): state and actions.
    required property var widget
    // Scroll view the pickers keep their popups inside.
    required property Item pickerScroll

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    // —— Favorites ——
    KantePlasmaHeading {
    Layout.fillWidth: true
        level: 4
        opacity: widget.showFavoritesHere ? 1 : 0
        visible: opacity > 0 && widget.isConfigured
                 && (widget.pinnedEntries.length > 0 || widget.loadingPinned || !widget.compactPopupLayout)
        text: i18n("Favorites")
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    GridLayout {
        id: favoritesGrid
    Layout.fillWidth: true
        opacity: widget.showFavoritesHere && !widget.loadingPinned && widget.pinnedEntries.length > 0 ? 1 : 0
        visible: opacity > 0
        // Kante: two tiles per row (one when narrow).
        columns: KanteStyle.active
                 ? (width >= Kirigami.Units.gridUnit * 16 ? 2 : 1)
                 : Math.max(1, Math.floor(width / (Kirigami.Units.gridUnit * TouchUi.favoriteCellGu)))
        rowSpacing: TouchUi.smallSpacing
        columnSpacing: TouchUi.smallSpacing
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Repeater {
            model: widget.favoritesVisibleCount
            delegate: ActivityListRow {
                presentation: ActivityListRow.Presentation.Tile
                readonly property var pinSheet: Favorites.asTimesheet(widget.pinnedEntries[index])
                readonly property string pinKey: widget.switchHintKey(pinSheet)
                Layout.fillWidth: true
                customerColor: widget.pinnedEntries[index].customerColor || KimaiApi.DEFAULT_CUSTOMER_COLOR
                titleText: widget.pinnedEntries[index].activityName
                subtitleText: {
                    var entry = widget.pinnedEntries[index]
                    var bits = []
                    if (entry.customerName) {
                        bits.push(entry.customerName)
                    }
                    if (entry.projectName) {
                        bits.push(entry.projectName)
                    }
                    return bits.join(" · ")
                }
                rowEnabled: widget.isConfigured && !widget.isBusy && widget.connectionState !== "error"
                showPlayIcon: true
                showHistoryActions: true
                canPin: true
                isPinned: true
                runningHintVisible: widget.alreadyRunningHintKey === pinKey
                runningHintText: i18n("Already running.")
                runningHintCounterText: widget.isTracking
                                        ? KimaiApi.formatDurationPanel(widget.elapsedSeconds)
                                        : ""
                onRowActivated: widget.startPinned(widget.pinnedEntries[index])
                onPinRequested: {
                    var entry = widget.pinnedEntries[index]
                    Plasmoid.configuration.pinnedActivities = Favorites.togglePinned(
                        Plasmoid.configuration.pinnedActivities,
                        entry.projectId, entry.activityId)
                    widget.refreshPinnedEntries(true)
                }
                tooltipText: {
                    var entry = widget.pinnedEntries[index]
                    var bits = []
                    if (entry.customerName) {
                        bits.push(entry.customerName)
                    }
                    if (entry.projectName) {
                        bits.push(entry.projectName)
                    }
                    if (entry.activityName) {
                        bits.push(entry.activityName)
                    }
                    return bits.join(" · ")
                }
            }
        }
    }

    ColumnLayout {
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing
        opacity: widget.showFavoritesHere
                 && widget.isConfigured && !widget.loadingPinned
                 && widget.pinnedEntries.length === 0 && !widget.compactPopupLayout ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("No favorites yet")
            font.bold: true
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Pin frequent project/activity pairs in the widget settings.")
            opacity: 0.75
            font.pointSize: KanteStyle.smallFont.pointSize
        }
        KantePlasmaButton {
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            text: i18n("Configure favorites")
            icon.name: "configure"
            onClicked: widget.openConfigure()
        }
    }

    LoadingRow {
    Layout.fillWidth: true
        visible: widget.showFavoritesHere && widget.loadingPinned && widget.pinnedEntries.length === 0
    }

    PlasmaComponents3.Label {
    Layout.fillWidth: true
        visible: widget.showFavoritesHere
                 && widget.compactPopupLayout
                 && widget.pinnedEntries.length > widget.favoritesVisibleCount
        text: i18n("+%1 more in settings", widget.pinnedEntries.length - widget.favoritesVisibleCount)
        opacity: 0.7
        font.pointSize: KanteStyle.smallFont.pointSize
    }

    // —— Detected trips (kimai-anfahrten, A5) ——
    KantePlasmaHeading {
    Layout.fillWidth: true
        level: 4
        visible: widget.canEditTrips && widget.tripSuggestions.length > 0
        text: i18n("Detected trips")
    }
    TripSuggestionList {
    Layout.fillWidth: true
        visible: widget.canEditTrips && widget.tripSuggestions.length > 0
        suggestions: widget.tripSuggestions
        maxRows: widget.compactPopupLayout ? 2 : 3
        busy: widget.isBusy || widget.tripBusy
        canEdit: widget.canEditTrips
        meta: widget.mileageMeta
        onAcceptRequested: function(sg) { widget.acceptTripSuggestion(sg) }
        onDismissRequested: function(sg) { widget.dismissTripSuggestion(sg) }
        onEditRequested: function(sg) {
            widget.openTripSheet(Mileage.formFromSuggestion(widget.mileagePing, sg), null, "", sg)
        }
    }

    // —— Recent ——
    KantePlasmaHeading {
    Layout.fillWidth: true
        level: 4
        opacity: widget.showRecentHere && widget.isConfigured ? 1 : 0
        visible: opacity > 0
        text: i18n("Recent")
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    ColumnLayout {
    Layout.fillWidth: true
        spacing: 0
        opacity: widget.showRecentHere && widget.isConfigured ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Repeater {
            model: widget.loadingRecent && widget.recentTimesheets.length === 0 ? 0 : widget.recentVisibleCount
            delegate: ActivityListRow {
                readonly property var ts: widget.recentTimesheets[index]
                readonly property string tsKey: widget.switchHintKey(ts)
                Layout.fillWidth: true
                readonly property var barInfo: KimaiApi.barColorInfoFromTimesheet(
                    widget.recentTimesheets[index], widget.customersById)
                customerColor: barInfo.color
                titleText: KimaiApi.displayActivityName(
                    widget.recentTimesheets[index], widget.allActivities, widget.activitiesByProject)
                timeText: DTF.entryTimeLabel(ts.begin, ts.end, new Date(), i18n("now"))
                durationText: {
                    var secs = KimaiApi.timesheetDurationSeconds(ts)
                    return secs > 0 ? DTF.hoursMinutes(secs) : ""
                }
                subtitleText: {
                    var ts = widget.recentTimesheets[index]
                    if (KanteStyle.active) {
                        // Time and duration have their own columns in the Kante time line.
                        return KimaiApi.displayProjectName(ts, widget.projects)
                    }
                    var bits = [KimaiApi.displayProjectName(ts, widget.projects)]
                    var secs = KimaiApi.timesheetDurationSeconds(ts)
                    if (secs > 0) {
                        bits.push(KimaiApi.formatDurationShort(secs))
                    }
                    bits.push(widget.formatRelativeTime(ts.end || ts.begin))
                    return bits.join(" · ")
                }
                rowEnabled: widget.isConfigured && !widget.isBusy && widget.connectionState !== "error"
                runningHintVisible: widget.alreadyRunningHintKey === tsKey
                runningHintText: i18n("Already running.")
                runningHintCounterText: widget.isTracking
                                        ? KimaiApi.formatDurationPanel(widget.elapsedSeconds)
                                        : ""
                showHistoryActions: {
                    var sheet = widget.recentTimesheets[index]
                    if (!sheet || !sheet.end || widget.timesheetIsRunning(sheet)) {
                        return false
                    }
                    return true
                }
                canEditStopped: widget.providerCapabilities.editStopped
                canDeleteEntry: widget.providerCapabilities.deleteEntry
                canSplitEntry: widget.providerCapabilities.editStopped
                               && !!(widget.recentTimesheets[index] && widget.recentTimesheets[index].end)
                canPin: true
                canLogTrip: widget.canEditTrips
                onTripRequested: widget.openTripForTimesheet(widget.recentTimesheets[index])
                isPinned: Favorites.isPinned(Plasmoid.configuration.pinnedActivities, KimaiApi.projectId(widget.recentTimesheets[index]), KimaiApi.activityId(widget.recentTimesheets[index]))
                onRowActivated: widget.requestRestartFromRecent(widget.recentTimesheets[index])
                onEditRequested: widget.openStoppedEdit(widget.recentTimesheets[index])
                onDeleteRequested: widget.requestDeleteStopped(widget.recentTimesheets[index])
                onSplitRequested: widget.requestSplitStopped(widget.recentTimesheets[index])
                onPinRequested: {
                    var ts = widget.recentTimesheets[index]
                    Plasmoid.configuration.pinnedActivities = Favorites.togglePinned(
                        Plasmoid.configuration.pinnedActivities,
                        KimaiApi.projectId(ts), KimaiApi.activityId(ts))
                    widget.refreshPinnedEntries(true)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: widget.loadingRecent && widget.recentTimesheets.length === 0
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: widget.compactPopupLayout ? 2 : 3
                LoadingRow { Layout.fillWidth: true }
            }
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
            visible: !widget.loadingRecent && widget.recentTimesheets.length === 0 && widget.connectionState !== "error"
            icon.name: "view-history"
            text: i18n("No recent activities")
            explanation: i18n("Start tracking to build your recent list.")
        }
    }

    // —— New / switch ——
    KantePlasmaButton {
    Layout.fillWidth: true
        Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
        opacity: widget.showNewActivityHere && widget.isConfigured
                 && widget.compactPopupLayout && !widget.showNewActivityForm ? 1 : 0
        visible: opacity > 0
        text: widget.isTracking ? i18n("Switch to another activity…") : i18n("Start something else…")
        icon.name: "list-add"
        onClicked: widget.showNewActivityForm = true
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    KantePlasmaHeading {
    Layout.fillWidth: true
        level: 4
        opacity: widget.showNewActivityHere && widget.isConfigured && widget.showNewActivityForm ? 1 : 0
        visible: opacity > 0
        text: widget.isTracking ? i18n("Switch activity") : i18n("New activity")
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    LoadingRow {
    Layout.fillWidth: true
        visible: widget.showNewActivityHere && widget.showNewActivityForm && widget.loadingProjects
                 && widget.projectPickerModel.length === 0
    }

    ProjectActivityPickers {
        id: switchPickers
        Component.onCompleted: widget.switchPickersRef = switchPickers
        Component.onDestruction: {
            if (widget.switchPickersRef === switchPickers) {
                widget.switchPickersRef = null
            }
        }
    Layout.fillWidth: true
        visible: widget.showNewActivityHere && widget.showNewActivityForm && !widget.loadingProjects
        projectPickerModel: widget.projectPickerModel
        activityPickerModel: widget.activityPickerModel
        activitySectionTitles: widget.activitySectionTitles
        pickerOpenBelow: widget.pickerOpenBelow
        pickerViewport: pickerScroll
        projectEnabled: widget.isConfigured && !widget.isBusy && widget.connectionState !== "error"
        activityEnabled: widget.isConfigured && !widget.isBusy && widget.connectionState !== "error"
                     && !!widget.selectedProjectId
        projectVisible: !widget.loadingProjects
        activityVisible: !widget.loadingProjects || widget.activityPickerModel.length > 0
        showCreateActions: widget.providerCapabilities.createEntities
        onAboutToOpenPicker: function(projectField, activityField) {
            widget.updatePickerOpenDirection(projectField, activityField)
        }
        onProjectActivated: function(index) {
            if (index < 0 || index >= switchPickers.projectPickerModel.length) {
                widget.loadActivitiesForProject(0)
                return
            }
            widget.loadActivitiesForProject(switchPickers.projectPickerModel[index].value.id)
        }
        onCreateProjectRequested: widget.openCreateEntity("project")
        onCreateActivityRequested: widget.openCreateEntity("activity")
    }

    KanteTextField {
        id: descriptionField
        Component.onCompleted: widget.descriptionFieldRef = descriptionField
        Component.onDestruction: {
            if (widget.descriptionFieldRef === descriptionField) {
                widget.descriptionFieldRef = null
            }
        }
    Layout.fillWidth: true
        visible: widget.showNewActivityHere && widget.showNewActivityForm
        enabled: widget.isConfigured && !widget.isBusy && widget.connectionState !== "error"
        placeholderText: i18n("Description (optional)")
    }

    RowLayout {
    Layout.fillWidth: true
        visible: widget.showNewActivityHere && widget.showNewActivityForm
    spacing: Kirigami.Units.smallSpacing

        KantePlasmaButton {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            enabled: widget.isConfigured && !widget.isBusy && !widget.isTracking && widget.connectionState !== "error"
                     && switchPickers.projectCombo.currentIndex >= 0
                     && switchPickers.activityCombo.currentIndex >= 0
            text: i18n("Start")
            icon.name: "media-playback-start"
            onClicked: {
                var project = switchPickers.projectCombo.currentItem.value
                var activity = switchPickers.activityCombo.currentItem.value
                widget.startTracking(project.id, activity.id, project.name, activity.name, descriptionField.text)
            }
        }

        KantePlasmaButton {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            visible: widget.isTracking
            enabled: widget.isConfigured && !widget.isBusy && widget.connectionState !== "error"
                     && switchPickers.projectCombo.currentIndex >= 0
                     && switchPickers.activityCombo.currentIndex >= 0
            text: i18n("Switch")
            icon.name: "media-skip-forward"
            onClicked: {
                var project = switchPickers.projectCombo.currentItem.value
                var activity = switchPickers.activityCombo.currentItem.value
                widget.switchToActivity(project.id, activity.id, project.name, activity.name, descriptionField.text)
            }
        }

        KantePlasmaButton {
            visible: widget.compactPopupLayout
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            text: i18n("Cancel")
            onClicked: widget.showNewActivityForm = false
        }
    }
}
