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

ConfigPage {
    id: page

    readonly property string kwalletScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/kwallet.sh"))
    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/sharedConfig.sh"))
    readonly property string catalogCacheScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/catalogCache.sh"))
    readonly property int pageMargin: Kirigami.Units.gridUnit
    /** Extra space so list text does not sit against the scrollbar. */
    readonly property int scrollGutter: Kirigami.Units.gridUnit

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
    property int effectiveCustomerPct: 22
    property int effectiveProjectPct: 22
    property int effectiveActivityPct: 22

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

    /** Distinction only — theme colors differ between plasmoid and settings dialog. */
    function distinctionKey() {
        return (plasmoid.configuration.colorDistinctionEnabled !== false ? "1" : "0")
            + "|" + String(plasmoid.configuration.colorSimilarityPercent || 22)
    }

    function distinctionKeyOf(settingsKey) {
        var parts = String(settingsKey || "").split("|")
        if (parts.length < 2) {
            return ""
        }
        return parts[0] + "|" + parts[1]
    }

    function themePaletteFromSettingsKey(settingsKey) {
        var parts = String(settingsKey || "").split("|")
        // enabled|percent|highlight|positive|neutral|negative|link|active|visited
        if (parts.length < 9) {
            return null
        }
        return [parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8]]
    }

    function applyColorOptions() {
        // Prefer the palette that produced the cached groups (widget), not the
        // settings-dialog theme — otherwise “Reload from server” reshuffles colors.
        var cached = MaintenanceCache.load()
        var fromCache = page.themePaletteFromSettingsKey(cached.settingsKey)
        if (fromCache) {
            ColorDistinct.setThemePalette(fromCache)
        } else {
            ColorDistinct.setThemePalette([
                Kirigami.Theme.highlightColor,
                Kirigami.Theme.positiveTextColor,
                Kirigami.Theme.neutralTextColor,
                Kirigami.Theme.negativeTextColor,
                Kirigami.Theme.linkColor,
                Kirigami.Theme.activeTextColor,
                Kirigami.Theme.visitedLinkColor
            ])
        }
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
        page.effectiveCustomerPct = ColorDistinct.effectiveSimilarityPercent("customer")
        page.effectiveProjectPct = ColorDistinct.effectiveSimilarityPercent("project")
        page.effectiveActivityPct = ColorDistinct.effectiveSimilarityPercent("activity")
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
        var eff = cached.effectiveSimilarity || {}
        if (typeof eff.customer === "number") {
            page.effectiveCustomerPct = eff.customer
        }
        if (typeof eff.project === "number") {
            page.effectiveProjectPct = eff.project
        }
        if (typeof eff.activity === "number") {
            page.effectiveActivityPct = eff.activity
        }
        page.statusText = cached.statusText
            || i18n("Loaded %1 customers, %2 projects, %3 activities. %4 clash group(s), %5 color(s) shifted.",
                    page.customers.length, page.projects.length, page.activities.length,
                    page.groupCount, page.shiftedCount)
    }

    function persistCache() {
        var prev = MaintenanceCache.load()
        var settingsKey = page.settingsFingerprint()
        // Never replace the theme half from the settings process — it differs
        // from plasmashell and would reshuffle colors on the next rebuild.
        if (prev.settingsKey) {
            var oldParts = String(prev.settingsKey).split("|")
            if (oldParts.length >= 9) {
                settingsKey = page.distinctionKey() + "|" + oldParts.slice(2).join("|")
            }
        }
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
            settingsKey: settingsKey,
            statusText: page.statusText,
            effectiveSimilarity: {
                customer: page.effectiveCustomerPct,
                project: page.effectiveProjectPct,
                activity: page.effectiveActivityPct
            }
        })
        Secret.saveCatalogCache(execSource, page.catalogCacheScript, MaintenanceCache.exportPayload())
    }

    /**
     * Show disk/memory catalog immediately. Do not recompute clash groups on open
     * unless distinction settings changed or groups are missing — theme fingerprints
     * differ between plasmashell and the settings process and used to force a full
     * ColorDistinct.rebuild every visit.
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

        function continueAfterLocal() {
            if (MaintenanceCache.hasCatalog(profileId)) {
                page.applyCachedCatalog()
                var cached = MaintenanceCache.load()
                var hasGroups = (cached.customerGroups && cached.customerGroups.length)
                    || (cached.projectGroups && cached.projectGroups.length)
                    || (cached.activityGroups && cached.activityGroups.length)
                var distinctionChanged = page.distinctionKeyOf(cached.settingsKey) !== page.distinctionKey()
                if (distinctionChanged || (!hasGroups && (page.customers.length || page.projects.length || page.activities.length))) {
                    page.rebuildRows()
                    page.applyStatusAfterLoad()
                    page.persistCache()
                }
                if (!forceRefresh && MaintenanceCache.isFresh(profileId)) {
                    return
                }
                if (!forceRefresh && MaintenanceCache.isFetching()) {
                    return
                }
                // Background refresh — keep cached status, do not flash “Updating…”.
                page.fetchCatalogFromApi(forceRefresh, profileId, true)
                return
            }
            page.fetchCatalogFromApi(forceRefresh, profileId, false)
        }

        if (MaintenanceCache.hasCatalog(profileId)) {
            continueAfterLocal()
            return
        }

        Secret.loadCatalogCache(execSource, page.catalogCacheScript, function(payload) {
            if (payload && String(payload.profileId || "") === String(profileId)) {
                MaintenanceCache.hydrate(payload)
            }
            continueAfterLocal()
        })
    }

    function fetchCatalogFromApi(forceRefresh, profileId, hadCache) {
        if (!hadCache || forceRefresh) {
            statusText = i18n("Loading customers, projects, and activities…")
        }

        MaintenanceCache.setFetching(true)
        Secret.load(execSource, page.kwalletScript, page.activeProfile.id, function(token, err) {
            if (err || !token) {
                MaintenanceCache.setFetching(false)
                if (!hadCache) {
                    statusText = i18n("Save an API token on the Connection tab first.")
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
                var prev = MaintenanceCache.load()
                var distinctionChanged = page.distinctionKeyOf(prev.settingsKey) !== page.distinctionKey()
                var hadGroups = page.groupCount > 0
                    || (prev.customerGroups && prev.customerGroups.length)
                    || (prev.projectGroups && prev.projectGroups.length)
                    || (prev.activityGroups && prev.activityGroups.length)
                page.customers = nextCustomers
                page.projects = nextProjects
                page.activities = nextActivities
                // Server reload must not reshuffle colors. Rebuild only when
                // distinction settings changed or we have no groups yet.
                if (distinctionChanged || !hadGroups) {
                    page.rebuildRows()
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

    // Theme accents differ in the settings process; cached group colors stay valid.
    // Rebuild only when the user changes distinction settings (Connections below).

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

    Component.onDestruction: Secret.cancelAll(execSource)

    onPageEntered: {
        // Show catalog immediately — do not wait for shared.json.
        page.loadCatalog(false)
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
            }
        })
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: page.pageMargin
        anchors.rightMargin: page.pageMargin
        anchors.topMargin: page.pageMargin
        anchors.bottomMargin: page.pageMargin
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
                         page.effectiveCustomerPct,
                         page.effectiveProjectPct,
                         page.effectiveActivityPct)
                  : i18n("Distinction off — enable it in Display settings.")
        }

        QQC2.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.supportsColorDistinction
            clip: true

            ColumnLayout {
                width: Math.max(1, scroll.availableWidth - page.scrollGutter)
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
