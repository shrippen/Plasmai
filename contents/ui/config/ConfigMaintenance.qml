import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import "../../code/secret.js" as Secret
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/timeTracker.js" as TimeTracker
import "../../code/profiles.js" as Profiles
import "../../code/sharedConfig.js" as SharedConfig
import "../../code/colorDistinct.js" as ColorDistinct
import "../../code/maintenanceCache.js" as MaintenanceCache

Item {
    id: page

    readonly property string kwalletScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/kwallet.sh"))
    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/sharedConfig.sh"))
    readonly property int pageMargin: Kirigami.Units.gridUnit

    readonly property var activeProfile: Profiles.profileById(
        Profiles.parseProfiles(plasmoid.configuration.profilesJson, plasmoid.configuration.kimaiUrl),
        plasmoid.configuration.activeProfileId || "default"
    )
    readonly property var tracker: TimeTracker.api(activeProfile && activeProfile.provider
        ? activeProfile.provider : "kimai")
    readonly property var providerCapabilities: TimeTracker.providerCapabilities(
        activeProfile && activeProfile.provider ? activeProfile.provider : "kimai")
    readonly property bool supportsColorDistinction: providerCapabilities.colorDistinction

    property string statusText: ""
    property var customers: []
    property var projects: []
    property var activities: []
    property var customerGroups: []
    property var projectGroups: []
    property var activityGroups: []
    property int shiftedCount: 0
    property int groupCount: 0

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            Secret.handleData(execSource, sourceName, data)
        }
    }

    readonly property string themePaletteKey: [
        String(Kirigami.Theme.highlightColor),
        String(Kirigami.Theme.positiveTextColor),
        String(Kirigami.Theme.neutralTextColor),
        String(Kirigami.Theme.negativeTextColor),
        String(Kirigami.Theme.linkColor),
        String(Kirigami.Theme.activeTextColor),
        String(Kirigami.Theme.visitedLinkColor)
    ].join("|")

    function settingsFingerprint() {
        return [
            plasmoid.configuration.colorDistinctionEnabled !== false ? "1" : "0",
            String(plasmoid.configuration.colorSimilarityPercent || 22),
            page.themePaletteKey
        ].join("|")
    }

    function applyColorOptions() {
        ColorDistinct.setThemePalette([
            Kirigami.Theme.highlightColor,
            Kirigami.Theme.positiveTextColor,
            Kirigami.Theme.neutralTextColor,
            Kirigami.Theme.negativeTextColor,
            Kirigami.Theme.linkColor,
            Kirigami.Theme.activeTextColor,
            Kirigami.Theme.visitedLinkColor
        ])
        ColorDistinct.configure(
            page.supportsColorDistinction
                && plasmoid.configuration.colorDistinctionEnabled !== false,
            plasmoid.configuration.colorSimilarityPercent || 22
        )
    }

    function countShifted(groups) {
        var n = 0
        for (var g = 0; g < (groups || []).length; g++) {
            var entries = groups[g].entries || []
            for (var i = 0; i < entries.length; i++) {
                if (entries[i].shifted) {
                    n++
                }
            }
        }
        return n
    }

    function rebuildRows() {
        page.applyColorOptions()
        // Respect ColorDistinct fingerprint cache (do not force).
        ColorDistinct.rebuild(page.customers, page.projects, page.activities, false)
        page.customerGroups = ColorDistinct.maintenanceGroups("customer", page.customers)
        page.projectGroups = ColorDistinct.maintenanceGroups("project", page.projects)
        page.activityGroups = ColorDistinct.maintenanceGroups("activity", page.activities)
        page.groupCount = page.customerGroups.length + page.projectGroups.length + page.activityGroups.length
        page.shiftedCount = page.countShifted(page.customerGroups)
            + page.countShifted(page.projectGroups)
            + page.countShifted(page.activityGroups)
    }

    /** Ensure ColorDistinct maps exist without rebuilding clash-group rows. */
    function syncColorMapsOnly() {
        page.applyColorOptions()
        ColorDistinct.rebuild(page.customers, page.projects, page.activities, false)
    }

    function applyStatusAfterLoad() {
        if (plasmoid.configuration.colorDistinctionEnabled === false) {
            statusText = i18n("Color distinction is off. Enable it in Display settings to see clash groups.")
        } else if (page.groupCount === 0) {
            statusText = i18n("Loaded %1 customers, %2 projects, %3 activities. No similar colors within a category.",
                              page.customers.length, page.projects.length, page.activities.length)
        } else {
            statusText = i18n("Loaded %1 customers, %2 projects, %3 activities. %4 clash group(s), %5 color(s) shifted.",
                              page.customers.length, page.projects.length, page.activities.length,
                              page.groupCount, page.shiftedCount)
        }
    }

    function applyCachedCatalog() {
        var cached = MaintenanceCache.load()
        page.customers = cached.customers
        page.projects = cached.projects
        page.activities = cached.activities
        page.customerGroups = cached.customerGroups
        page.projectGroups = cached.projectGroups
        page.activityGroups = cached.activityGroups
        page.shiftedCount = cached.shiftedCount
        page.groupCount = cached.groupCount
        page.statusText = cached.statusText
            || i18n("Loaded %1 customers, %2 projects, %3 activities. %4 clash group(s), %5 color(s) shifted.",
                    page.customers.length, page.projects.length, page.activities.length,
                    page.groupCount, page.shiftedCount)
    }

    function persistCache() {
        MaintenanceCache.store(page.activeProfile ? page.activeProfile.id : "", {
            customers: page.customers,
            projects: page.projects,
            activities: page.activities,
            entityFingerprint: MaintenanceCache.entityFingerprint(
                page.customers, page.projects, page.activities),
            customerGroups: page.customerGroups,
            projectGroups: page.projectGroups,
            activityGroups: page.activityGroups,
            shiftedCount: page.shiftedCount,
            groupCount: page.groupCount,
            settingsKey: page.settingsFingerprint(),
            statusText: page.statusText
        })
    }

    /**
     * Apply any in-process catalog immediately. Recompute clash groups only when
     * distinction settings / theme changed. Hit the API only when forced, missing,
     * or older than FRESH_MS (stale-while-revalidate).
     */
    function loadCatalog(forceRefresh) {
        if (!page.supportsColorDistinction) {
            statusText = i18n("Color distinction is only available for Kimai profiles.")
            return
        }
        if (!page.activeProfile || !page.activeProfile.url) {
            statusText = i18n("Configure a server URL on the Connection tab first.")
            return
        }
        var profileId = page.activeProfile.id
        var settingsKey = page.settingsFingerprint()
        var hadCache = MaintenanceCache.hasCatalog(profileId)

        if (hadCache) {
            page.applyCachedCatalog()
            if (!MaintenanceCache.groupsMatch(settingsKey)) {
                page.rebuildRows()
                page.applyStatusAfterLoad()
                page.persistCache()
            } else {
                page.syncColorMapsOnly()
            }
            if (!forceRefresh && MaintenanceCache.isFresh(profileId)) {
                return
            }
            if (!forceRefresh && MaintenanceCache.isFetching()) {
                return
            }
        }

        if (!hadCache || forceRefresh) {
            statusText = i18n("Loading customers, projects, and activities…")
        } else {
            statusText = i18n("Updating catalog…")
        }

        MaintenanceCache.setFetching(true)
        Secret.load(execSource, page.kwalletScript, page.activeProfile.id, function(token, err) {
            if (err || !token) {
                MaintenanceCache.setFetching(false)
                if (!hadCache) {
                    statusText = i18n("Save an API token on the Connection tab first.")
                } else {
                    page.applyStatusAfterLoad()
                }
                return
            }
            TimeTracker.applySession(page.activeProfile.provider || "kimai", page.activeProfile)
            var url = TimeTracker.resolveUrl(page.activeProfile)
            var customersDone = false
            var projectsDone = false
            var activitiesDone = false
            var customersResult = null
            var projectsResult = null
            var activitiesResult = null

            function tryFinish() {
                if (!customersDone || !projectsDone || !activitiesDone) {
                    return
                }
                MaintenanceCache.setFetching(false)
                var nextCustomers = (customersResult && customersResult.ok) ? (customersResult.data || []) : []
                var nextProjects = (projectsResult && projectsResult.ok) ? (projectsResult.data || []) : []
                var nextActivities = (activitiesResult && activitiesResult.ok) ? (activitiesResult.data || []) : []
                var nextFp = MaintenanceCache.entityFingerprint(nextCustomers, nextProjects, nextActivities)
                var prev = MaintenanceCache.load()
                var entitiesChanged = nextFp !== prev.entityFingerprint
                page.customers = nextCustomers
                page.projects = nextProjects
                page.activities = nextActivities
                if (entitiesChanged || !MaintenanceCache.groupsMatch(settingsKey)) {
                    page.rebuildRows()
                } else {
                    page.syncColorMapsOnly()
                }
                page.applyStatusAfterLoad()
                page.persistCache()
            }

            page.tracker.loadCustomers(url, token, function(result) {
                customersResult = result
                customersDone = true
                tryFinish()
            })
            page.tracker.loadProjects(url, token, function(result) {
                projectsResult = result
                projectsDone = true
                tryFinish()
            })
            if (typeof page.tracker.loadAllActivities === "function") {
                page.tracker.loadAllActivities(url, token, function(result) {
                    activitiesResult = result
                    activitiesDone = true
                    tryFinish()
                })
            } else {
                activitiesResult = { ok: true, data: [] }
                activitiesDone = true
                tryFinish()
            }
        })
    }

    onThemePaletteKeyChanged: {
        if (page.customers.length || page.projects.length || page.activities.length) {
            page.rebuildRows()
            page.applyStatusAfterLoad()
            page.persistCache()
        }
    }

    Connections {
        target: plasmoid.configuration
        function onColorDistinctionEnabledChanged() {
            if (page.customers.length || page.projects.length || page.activities.length) {
                page.rebuildRows()
                page.applyStatusAfterLoad()
                page.persistCache()
            }
        }
        function onColorSimilarityPercentChanged() {
            if (page.customers.length || page.projects.length || page.activities.length) {
                page.rebuildRows()
                page.applyStatusAfterLoad()
                page.persistCache()
            }
        }
        function onActiveProfileIdChanged() {
            page.loadCatalog(false)
        }
    }

    Component.onCompleted: {
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
            }
            page.loadCatalog(false)
        })
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: page.pageMargin
        spacing: Kirigami.Units.smallSpacing

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !page.supportsColorDistinction
            icon.name: "color-picker"
            text: i18n("Color maintenance is for Kimai")
            explanation: i18n("Clockify, Toggl, and SolidTime do not expose Kimai-style customer / project / activity colors, so clash groups and color shifting are hidden for those profiles.")
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: page.supportsColorDistinction
            wrapMode: Text.WordWrap
            text: i18n("Only colors that clash within a category are listed. Each group starts with the entry that kept the Kimai color; shifted variants follow. Unique colors are hidden.")
        }

        RowLayout {
            Layout.fillWidth: true
            visible: page.supportsColorDistinction
            PlasmaComponents3.Button {
                text: i18n("Reload from server")
                icon.name: "view-refresh"
                onClicked: page.loadCatalog(true)
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.8
                text: page.statusText
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: page.supportsColorDistinction
            wrapMode: Text.WordWrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.75
            text: plasmoid.configuration.colorDistinctionEnabled !== false
                  ? i18n("Distinction on · configured %1% · effective customers %2% / projects %3% / activities %4%",
                         plasmoid.configuration.colorSimilarityPercent || 22,
                         ColorDistinct.effectiveSimilarityPercent("customer"),
                         ColorDistinct.effectiveSimilarityPercent("project"),
                         ColorDistinct.effectiveSimilarityPercent("activity"))
                  : i18n("Distinction off — enable it in Display settings.")
        }

        QQC2.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.supportsColorDistinction
            clip: true

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Kirigami.Units.largeSpacing

                // Customers
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: i18n("Customers")
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: page.customerGroups.length === 0
                    opacity: 0.7
                    text: i18n("No similar colors in this category.")
                }
                Repeater {
                    model: page.customerGroups
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        readonly property var group: modelData

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            height: 1
                            color: Kirigami.Theme.textColor
                            opacity: 0.15
                            visible: index > 0
                        }

                        Repeater {
                            model: group.entries
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                readonly property var entry: modelData

                                Rectangle {
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    radius: width / 4
                                    color: entry.original
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.2)
                                }
                                PlasmaComponents3.Label {
                                    text: "→"
                                    opacity: entry.shifted ? 1 : 0.35
                                }
                                Rectangle {
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    radius: width / 4
                                    color: entry.display
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.2)
                                }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.bold: !!entry.keeper
                                    text: entry.name
                                }
                                PlasmaComponents3.Label {
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    opacity: 0.75
                                    text: entry.keeper && !entry.shifted
                                          ? i18n("kept")
                                          : (entry.shifted ? i18n("shifted") : "")
                                }
                            }
                        }
                    }
                }

                // Projects
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: i18n("Projects")
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: page.projectGroups.length === 0
                    opacity: 0.7
                    text: i18n("No similar colors in this category.")
                }
                Repeater {
                    model: page.projectGroups
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        readonly property var group: modelData

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            height: 1
                            color: Kirigami.Theme.textColor
                            opacity: 0.15
                            visible: index > 0
                        }

                        Repeater {
                            model: group.entries
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                readonly property var entry: modelData

                                Rectangle {
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    radius: width / 4
                                    color: entry.original
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.2)
                                }
                                PlasmaComponents3.Label {
                                    text: "→"
                                    opacity: entry.shifted ? 1 : 0.35
                                }
                                Rectangle {
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    radius: width / 4
                                    color: entry.display
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.2)
                                }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.bold: !!entry.keeper
                                    text: entry.name
                                }
                                PlasmaComponents3.Label {
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    opacity: 0.75
                                    text: entry.keeper && !entry.shifted
                                          ? i18n("kept")
                                          : (entry.shifted ? i18n("shifted") : "")
                                }
                            }
                        }
                    }
                }

                // Activities
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: i18n("Activities")
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: page.activityGroups.length === 0
                    opacity: 0.7
                    text: i18n("No similar colors in this category.")
                }
                Repeater {
                    model: page.activityGroups
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        readonly property var group: modelData

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            height: 1
                            color: Kirigami.Theme.textColor
                            opacity: 0.15
                            visible: index > 0
                        }

                        Repeater {
                            model: group.entries
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                readonly property var entry: modelData

                                Rectangle {
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    radius: width / 4
                                    color: entry.original
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.2)
                                }
                                PlasmaComponents3.Label {
                                    text: "→"
                                    opacity: entry.shifted ? 1 : 0.35
                                }
                                Rectangle {
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    radius: width / 4
                                    color: entry.display
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.2)
                                }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.bold: !!entry.keeper
                                    text: entry.name
                                }
                                PlasmaComponents3.Label {
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    opacity: 0.75
                                    text: entry.keeper && !entry.shifted
                                          ? i18n("kept")
                                          : (entry.shifted ? i18n("shifted") : "")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
