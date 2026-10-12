import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
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
 * Data and actions come from the session, view state from the widget root.
 */
ColumnLayout {
    id: listSection

    // The session layer (Session.qml): data and actions.
    required property QtObject session
    // Widget root (main.qml): view state and navigation only (editors, dialogs, flashes).
    required property var view
    // Scroll view the pickers keep their popups inside.
    required property Item pickerScroll

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    /** Kante time line: the shown Recent entries (indices) grouped by day. */
    readonly property var recentDays: {
        if (!KanteStyle.active) {
            return []
        }
        var indices = []
        for (var i = 0; i < view.recentVisibleCount; i++) {
            indices.push(i)
        }
        return DTF.groupByDay(indices, new Date(),
                              function(i) { return session.recent.list[i].begin })
    }

    /** Begin of an entry as a local clock time ("07:42"). */
    function beginClock(ts) {
        var b = ts && ts.begin ? DTF.parseStamp(ts.begin) : null
        return b && !isNaN(b.getTime()) ? DTF.formatLocaleTime(b.getHours(), b.getMinutes()) : ""
    }

    // —— New / switch: right below the timer card, opened from its start button ——
    KantePlasmaHeading {
    Layout.fillWidth: true
        level: 4
        opacity: view.showNewActivityHere && session.connection.configured && view.showNewActivityForm ? 1 : 0
        visible: opacity > 0
        text: session.timer.tracking ? i18n("Switch activity") : i18n("New activity")
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    LoadingRow {
    Layout.fillWidth: true
        visible: view.showNewActivityHere && view.showNewActivityForm && !session.catalog.loaded
                 && session.catalog.projectPickerModel.length === 0
    }

    ProjectActivityPickers {
        id: switchPickers
        Component.onCompleted: view.switchPickersRef = switchPickers
        Component.onDestruction: {
            if (view.switchPickersRef === switchPickers) {
                view.switchPickersRef = null
            }
        }
    Layout.fillWidth: true
        visible: view.showNewActivityHere && view.showNewActivityForm && session.catalog.loaded
        projectPickerModel: session.catalog.projectPickerModel
        activityPickerModel: view.activityPickerModel
        activitySectionTitles: view.activitySectionTitles
        pickerOpenBelow: view.pickerOpenBelow
        pickerViewport: pickerScroll
        projectEnabled: session.connection.configured && !session.busy && view.connectionState !== "error"
        activityEnabled: session.connection.configured && !session.busy && view.connectionState !== "error"
                     && !!view.selectedProjectId
        projectVisible: session.catalog.loaded
        activityVisible: session.catalog.loaded || view.activityPickerModel.length > 0
        showCreateActions: session.entries.canCreate
        onAboutToOpenPicker: function(projectField, activityField) {
            view.updatePickerOpenDirection(projectField, activityField)
        }
        onProjectActivated: function(index) {
            if (index < 0 || index >= switchPickers.projectPickerModel.length) {
                view.loadActivitiesForProject(0)
                return
            }
            view.loadActivitiesForProject(switchPickers.projectPickerModel[index].value.id)
        }
        onCreateProjectRequested: view.openCreateEntity("project")
        onCreateActivityRequested: view.openCreateEntity("activity")
    }

    KanteTextField {
        id: descriptionField
        Component.onCompleted: view.descriptionFieldRef = descriptionField
        Component.onDestruction: {
            if (view.descriptionFieldRef === descriptionField) {
                view.descriptionFieldRef = null
            }
        }
    Layout.fillWidth: true
        visible: view.showNewActivityHere && view.showNewActivityForm
        enabled: session.connection.configured && !session.busy && view.connectionState !== "error"
        placeholderText: i18n("Description (optional)")
    }

    RowLayout {
    Layout.fillWidth: true
        visible: view.showNewActivityHere && view.showNewActivityForm
    spacing: Kirigami.Units.smallSpacing

        KantePlasmaButton {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            enabled: session.connection.configured && !session.busy && !session.timer.tracking && view.connectionState !== "error"
                     && switchPickers.projectCombo.currentIndex >= 0
                     && switchPickers.activityCombo.currentIndex >= 0
            text: i18n("Start")
            icon.name: "media-playback-start"
            onClicked: {
                var project = switchPickers.projectCombo.currentItem.value
                var activity = switchPickers.activityCombo.currentItem.value
                session.timer.start(project.id, activity.id, project.name, activity.name, descriptionField.text)
            }
        }

        KantePlasmaButton {
            Layout.fillWidth: true
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            visible: session.timer.tracking
            enabled: session.connection.configured && !session.busy && view.connectionState !== "error"
                     && switchPickers.projectCombo.currentIndex >= 0
                     && switchPickers.activityCombo.currentIndex >= 0
            text: i18n("Switch")
            icon.name: "media-skip-forward"
            onClicked: {
                var project = switchPickers.projectCombo.currentItem.value
                var activity = switchPickers.activityCombo.currentItem.value
                session.timer.switchTo(project.id, activity.id, project.name, activity.name, descriptionField.text)
            }
        }

        KantePlasmaButton {
            visible: view.compactPopupLayout
            Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
            text: i18n("Cancel")
            onClicked: view.showNewActivityForm = false
        }
    }

    // —— Favorites ——
    KantePlasmaHeading {
    Layout.fillWidth: true
        level: 4
        opacity: view.showFavoritesHere ? 1 : 0
        visible: opacity > 0 && session.connection.configured
                 && (session.favorites.pinned.length > 0 || !view.compactPopupLayout)
        text: i18n("Favorites")
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    GridLayout {
        id: favoritesGrid
    Layout.fillWidth: true
        opacity: view.showFavoritesHere && session.favorites.pinned.length > 0 ? 1 : 0
        visible: opacity > 0
        // Kante: two tiles per row (one when narrow).
        columns: KanteStyle.active
                 ? (width >= Kirigami.Units.gridUnit * 16 ? 2 : 1)
                 : Math.max(1, Math.floor(width / (Kirigami.Units.gridUnit * TouchUi.favoriteCellGu)))
        rowSpacing: TouchUi.smallSpacing
        columnSpacing: TouchUi.smallSpacing
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Repeater {
            model: view.favoritesVisibleCount
            delegate: ActivityListRow {
                presentation: ActivityListRow.Presentation.Tile
                readonly property var pinSheet: Favorites.asTimesheet(session.favorites.pinned[index])
                readonly property string pinKey: session.timer.hintKey(pinSheet)
                Layout.fillWidth: true
                customerColor: session.favorites.pinned[index].customerColor || PlasmaiColors.entityFallback
                titleText: session.favorites.pinned[index].activityName
                subtitleText: {
                    var entry = session.favorites.pinned[index]
                    var bits = []
                    if (entry.customerName) {
                        bits.push(entry.customerName)
                    }
                    if (entry.projectName) {
                        bits.push(entry.projectName)
                    }
                    return bits.join(" · ")
                }
                rowEnabled: session.connection.configured && !session.busy && view.connectionState !== "error"
                showPlayIcon: true
                showHistoryActions: true
                canPin: true
                isPinned: true
                runningHintVisible: view.alreadyRunningHintKey === pinKey
                runningHintText: i18n("Already running.")
                runningHintCounterText: session.timer.tracking
                                        ? KimaiApi.formatDurationPanel(session.timer.elapsedSeconds)
                                        : ""
                onRowActivated: view.startPinned(session.favorites.pinned[index])
                onPinRequested: {
                    var entry = session.favorites.pinned[index]
                    session.favorites.toggle(entry.projectId, entry.activityId)
                }
                tooltipText: {
                    var entry = session.favorites.pinned[index]
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
        opacity: view.showFavoritesHere
                 && session.connection.configured
                 && session.favorites.pinned.length === 0 && !view.compactPopupLayout ? 1 : 0
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
            onClicked: view.openConfigure()
        }
    }

    PlasmaComponents3.Label {
    Layout.fillWidth: true
        visible: view.showFavoritesHere
                 && view.compactPopupLayout
                 && session.favorites.pinned.length > view.favoritesVisibleCount
        text: i18n("+%1 more in settings", session.favorites.pinned.length - view.favoritesVisibleCount)
        opacity: 0.7
        font.pointSize: KanteStyle.smallFont.pointSize
    }

    // —— Detected trips (kimai-anfahrten, A5) ——
    KantePlasmaHeading {
    Layout.fillWidth: true
        level: 4
        visible: session.trips.canEdit && view.tripSuggestions.length > 0 && !session.sync.offline
        text: i18n("Detected trips")
    }
    TripSuggestionList {
    Layout.fillWidth: true
        visible: session.trips.canEdit && view.tripSuggestions.length > 0 && !session.sync.offline
        suggestions: view.tripSuggestions
        maxRows: view.compactPopupLayout ? 2 : 3
        busy: session.busy || view.tripBusy
        canEdit: session.trips.canEdit
        meta: session.trips.meta
        onAcceptRequested: function(sg) { view.acceptTripSuggestion(sg) }
        onDismissRequested: function(sg) { view.dismissTripSuggestion(sg) }
        onEditRequested: function(sg) {
            view.openTripSheet(Mileage.formFromSuggestion(session.trips.ping, sg), null, "", sg)
        }
    }

    // —— Recent ——
    KantePlasmaHeading {
    Layout.fillWidth: true
        level: 4
        opacity: view.showRecentHere && session.connection.configured ? 1 : 0
        visible: opacity > 0
        text: i18n("Recent")
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    ColumnLayout {
    Layout.fillWidth: true
        spacing: 0
        opacity: view.showRecentHere && session.connection.configured ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // System: one flat list. Kante: the time line, grouped by day (variant B).
        Repeater {
            model: KanteStyle.active || (!session.recent.loaded && session.recent.list.length === 0) ? 0 : view.recentVisibleCount
            delegate: recentRow
        }

        Repeater {
            model: KanteStyle.active && !(!session.recent.loaded && session.recent.list.length === 0) ? listSection.recentDays : []
            delegate: ColumnLayout {
                id: dayGroup
                required property var modelData
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        text: DTF.dayHeaderLabel(dayGroup.modelData.date, new Date(), i18n("Today"), i18n("Yesterday"))
                        font: KanteStyle.labelFont()
                        color: KanteStyle.mutedTextColor
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: KanteStyle.ruleColor
                    }
                }

                Repeater {
                    model: dayGroup.modelData.entries
                    delegate: recentRow
                }
            }
        }

        Component {
            id: recentRow
            ActivityListRow {
                    required property var modelData
                    /** Index into session.recent.list (Repeater count or group model). */
                    readonly property int rowIndex: modelData
                    readonly property var ts: session.recent.list[rowIndex]
                    readonly property string tsKey: session.timer.hintKey(ts)
                    Layout.fillWidth: true
                    readonly property var barInfo: KimaiApi.barColorInfoFromTimesheet(
                        session.recent.list[rowIndex], session.catalog.customersById)
                    customerColor: barInfo.color
                    titleText: KimaiApi.displayActivityName(
                        session.recent.list[rowIndex], session.catalog.activities, session.catalog.activitiesByProject)
                    timeText: listSection.beginClock(ts)
                    durationText: {
                        var secs = KimaiApi.timesheetDurationSeconds(ts)
                        return secs > 0 ? DTF.hoursMinutes(secs) : ""
                    }
                    subtitleText: {
                        var ts = session.recent.list[rowIndex]
                        if (KanteStyle.active) {
                            // Time and duration have their own columns in the Kante time line.
                            return KimaiApi.displayProjectName(ts, session.catalog.projects)
                        }
                        var bits = [KimaiApi.displayProjectName(ts, session.catalog.projects)]
                        var secs = KimaiApi.timesheetDurationSeconds(ts)
                        if (secs > 0) {
                            bits.push(KimaiApi.formatDurationShort(secs))
                        }
                        bits.push(view.formatRelativeTime(ts.end || ts.begin))
                        return bits.join(" · ")
                    }
                    rowEnabled: session.connection.configured && !session.busy && view.connectionState !== "error"
                    runningHintVisible: view.alreadyRunningHintKey === tsKey
                    runningHintText: i18n("Already running.")
                    runningHintCounterText: session.timer.tracking
                                            ? KimaiApi.formatDurationPanel(session.timer.elapsedSeconds)
                                            : ""
                    showHistoryActions: {
                        var sheet = session.recent.list[rowIndex]
                        if (!sheet || !sheet.end || view.timesheetIsRunning(sheet)) {
                            return false
                        }
                        return true
                    }
                    canEditStopped: session.connection.capabilities.editStopped
                    canDeleteEntry: session.connection.capabilities.deleteEntry
                    // Split makes a second entry from one: online only, and not for an unsynced one.
                    canSplitEntry: session.connection.capabilities.editStopped && !session.sync.offline && !session.sync.isUnsynced(ts.id)
                    unsynced: session.sync.isUnsynced(ts.id)
                                   && !!(session.recent.list[rowIndex] && session.recent.list[rowIndex].end)
                    canPin: true
                    canLogTrip: session.trips.canEdit
                    onTripRequested: view.openTripForTimesheet(session.recent.list[rowIndex])
                    isPinned: session.favorites.isPinned(KimaiApi.projectId(session.recent.list[rowIndex]), KimaiApi.activityId(session.recent.list[rowIndex]))
                    onRowActivated: view.requestRestartFromRecent(session.recent.list[rowIndex])
                    onEditRequested: view.openStoppedEdit(session.recent.list[rowIndex])
                    onDeleteRequested: view.requestDeleteStopped(session.recent.list[rowIndex])
                    onSplitRequested: view.requestSplitStopped(session.recent.list[rowIndex])
                    onPinRequested: {
                        var ts = session.recent.list[rowIndex]
                        session.favorites.toggle(KimaiApi.projectId(ts), KimaiApi.activityId(ts))
                    }
                }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: !session.recent.loaded && session.recent.list.length === 0
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: view.compactPopupLayout ? 2 : 3
                LoadingRow { Layout.fillWidth: true }
            }
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
            visible: session.recent.loaded && session.recent.list.length === 0 && view.connectionState !== "error"
            icon.name: "view-history"
            text: i18n("No recent activities")
            explanation: i18n("Start tracking to build your recent list.")
        }
    }

}
