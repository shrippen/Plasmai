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
import "../../code/favorites.js" as Favorites
import "../../code/sharedConfig.js" as SharedConfig
import "../../code/colorDistinct.js" as ColorDistinct
import "../../code/maintenanceCache.js" as CatalogCache
import ".."

ConfigPage {
    id: page

    readonly property string kwalletScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/kwallet.sh"))
    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/sharedConfig.sh"))
    readonly property string catalogCacheScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/catalogCache.sh"))
    readonly property int pageMargin: Kirigami.Units.gridUnit

    readonly property var activeProfile: Profiles.profileById(
        Profiles.parseProfiles(plasmoid.configuration.profilesJson, plasmoid.configuration.kimaiUrl),
        plasmoid.configuration.activeProfileId || "default"
    )
    readonly property var tracker: TimeTracker.api(activeProfile && activeProfile.provider
        ? activeProfile.provider : "kimai")
    readonly property var providerCapabilities: TimeTracker.providerCapabilities(
        activeProfile && activeProfile.provider ? activeProfile.provider : "kimai")

    property var customers: []
    property var availableProjects: []
    property var allActivities: []
    property var projectRows: []
    property var projectActivities: ({})
    property var selectedProject: null
    property var activityRowModel: []
    property string projectsStatus: ""
    property string activitiesStatus: ""
    // Keep the loading indicator independent from the exact ellipsis character used
    // in translated status strings (e.g. "…"/"..."/"… ").
    property bool loadingProjects: false
    property bool loadingActivities: false

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            Secret.handleData(execSource, sourceName, data)
        }
    }

    Component.onDestruction: Secret.cancelAll(execSource)

    property bool loadScheduled: false
    property var pendingCatalogPayload: null
    property bool sharedLoadDone: false
    property bool catalogLoadDone: false

    WorkerScript {
        id: catalogParseWorker
        source: Qt.resolvedUrl("catalogParseWorker.js")
        onMessage: function(msg) {
            page.pendingCatalogPayload = msg.payload
            page.catalogLoadDone = true
            page.tryFinishCatalogLoad()
        }
    }

    Timer {
        id: contentLoadTimer
        interval: 16
        repeat: false
        onTriggered: {
            page.loadScheduled = false
            page.loadPageContent()
        }
    }

    function beginLoadingUi() {
        page.loadingProjects = true
        page.projectsStatus = i18n("Loading projects…")
    }

    function scheduleContentLoad() {
        page.beginLoadingUi()
        if (loadScheduled) {
            return
        }
        loadScheduled = true
        // Let the BusyIndicator paint before shell I/O / JSON work.
        contentLoadTimer.restart()
    }

    function tryFinishCatalogLoad() {
        if (!page.sharedLoadDone || !page.catalogLoadDone) {
            return
        }
        if (page.applyPayloadIfUsable(page.pendingCatalogPayload)) {
            return
        }
        if (!page.activeProfile || !page.activeProfile.url) {
            page.projectsStatus = i18n("Configure a Kimai URL on the Connection tab first.")
            page.loadingProjects = false
            return
        }
        page.fetchProjectsFromApi(false)
    }

    function loadPageContent() {
        if (!page.visible) {
            return
        }
        if (page.cfg_pinnedActivities && !pinnedField.text) {
            pinnedField.text = page.cfg_pinnedActivities
        }
        page.sharedLoadDone = false
        page.catalogLoadDone = false
        page.pendingCatalogPayload = null
        page.beginLoadingUi()

        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
                if (typeof shared.pinnedActivities === "string") {
                    pinnedField.text = shared.pinnedActivities
                    page.syncPinnedToCfg()
                }
            }
            page.sharedLoadDone = true
            page.tryFinishCatalogLoad()
        })

        var profileId = page.activeProfile ? page.activeProfile.id : "default"
        if (CatalogCache.hasCatalog(profileId)) {
            page.pendingCatalogPayload = CatalogCache.load()
            page.catalogLoadDone = true
            page.tryFinishCatalogLoad()
        } else {
            Secret.loadCatalogCacheText(execSource, page.catalogCacheScript, function(text, err) {
                if (err || !text) {
                    page.pendingCatalogPayload = null
                    page.catalogLoadDone = true
                    page.tryFinishCatalogLoad()
                    return
                }
                catalogParseWorker.sendMessage({ text: text })
            })
        }
    }

    onVisibleChanged: if (visible) scheduleContentLoad()
    onPageEntered: scheduleContentLoad()

    function loadSharedPinned() {
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
                if (typeof shared.pinnedActivities === "string") {
                    pinnedField.text = shared.pinnedActivities
                    page.syncPinnedToCfg()
                }
            }
        })
    }

    function persistShared() {
        Secret.persistSharedPatch(execSource, page.sharedConfigScript, plasmoid.configuration, {
            pinnedActivities: pinnedField.text
        })
    }

    function persistFavoritesConfig() {
        syncPinnedToCfg()
        page.persistShared()
        unsavedChanges = false
    }

    property var saveConfig: persistFavoritesConfig

    Timer {
        id: colorRebuildTimer
        interval: 32
        repeat: false
        onTriggered: page.applySharedColors()
    }

    function themePaletteFromSettingsKey(settingsKey) {
        var parts = String(settingsKey || "").split("|")
        if (parts.length < 9) {
            return null
        }
        return [parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8]]
    }

    function applyColorOptions() {
        var cached = CatalogCache.load()
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
            page.providerCapabilities.colorDistinction
                && plasmoid.configuration.colorDistinctionEnabled !== false,
            plasmoid.configuration.colorSimilarityPercent || 22
        )
    }

    function applySharedColors() {
        page.applyColorOptions()
        var cached = CatalogCache.load()
        var hasGroups = (cached.customerGroups && cached.customerGroups.length)
            || (cached.projectGroups && cached.projectGroups.length)
            || (cached.activityGroups && cached.activityGroups.length)
        if (hasGroups) {
            ColorDistinct.hydrateMapsFromGroups(
                page.customers, page.availableProjects, page.allActivities,
                cached.customerGroups, cached.projectGroups, cached.activityGroups)
        } else {
            ColorDistinct.rebuild(page.customers, page.availableProjects, page.allActivities, false)
        }
        page.projectRows = KimaiApi.projectsGroupedByCustomer(page.availableProjects, page.customers)
    }

    function applyCatalogEntities(customers, projects, activities) {
        page.customers = customers || []
        page.availableProjects = projects || []
        page.allActivities = activities || []
        // Paint the list immediately — ColorDistinct.rebuild can wait a tick.
        page.projectRows = KimaiApi.projectsGroupedByCustomer(page.availableProjects, page.customers)
        page.projectsStatus = i18n("Loaded %1 projects.", page.availableProjects.length)
        page.loadingProjects = false
        page.loadingActivities = false
        if (page.selectedProject) {
            var keepId = page.selectedProject.id
            var stillThere = null
            for (var i = 0; i < page.availableProjects.length; i++) {
                if (String(page.availableProjects[i].id) === String(keepId)) {
                    stillThere = page.availableProjects[i]
                    break
                }
            }
            if (stillThere) {
                page.showActivitiesForProject(stillThere)
            } else {
                page.selectedProject = null
                page.activityRowModel = []
                page.activitiesStatus = i18n("Select a project to pin activities.")
            }
        } else if (!page.selectedProject) {
            page.activityRowModel = []
            page.activitiesStatus = i18n("Select a project to pin activities.")
        }
        // Same display colors as Maintenance, from the catalog cache groups.
        colorRebuildTimer.restart()
    }

    function applyPayloadIfUsable(payload) {
        if (!payload || !(payload.projects || []).length) {
            return false
        }
        CatalogCache.hydrate(payload)
        page.applyCatalogEntities(payload.customers, payload.projects, payload.activities)
        return true
    }

    function loadProjects(forceRefresh) {
        var profileId = page.activeProfile ? page.activeProfile.id : "default"

        function afterCache(fromCache) {
            // Shared config only after catalog — one executable job at a time.
            page.loadSharedPinned()
            if (fromCache && !forceRefresh) {
                return
            }
            if (!page.activeProfile || !page.activeProfile.url) {
                if (!fromCache) {
                    projectsStatus = i18n("Configure a Kimai URL on the Connection tab first.")
                }
                page.loadingProjects = false
                return
            }
            page.fetchProjectsFromApi(fromCache)
        }

        if (!forceRefresh && CatalogCache.hasCatalog(profileId)) {
            var cached = CatalogCache.load()
            if (page.applyPayloadIfUsable(cached)) {
                afterCache(true)
                return
            }
        }

        if (!forceRefresh) {
            projectsStatus = i18n("Loading projects…")
            page.loadingProjects = true
        }

        // Disk cache via shell (Qt blocks XMLHttpRequest on file://).
        Secret.loadCatalogCache(execSource, page.catalogCacheScript, function(payload) {
            afterCache(page.applyPayloadIfUsable(payload))
        })
    }

    function fetchProjectsFromApi(hadCache) {
        if (!hadCache) {
            projectsStatus = i18n("Loading projects…")
            page.loadingProjects = true
        }
        Secret.load(execSource, page.kwalletScript, page.activeProfile.id, function(token, err) {
            if (err || !token) {
                if (!hadCache) {
                    projectsStatus = i18n("Save an API token on the Connection tab first.")
                }
                page.loadingProjects = false
                return
            }
            TimeTracker.applySession(page.activeProfile.provider || "kimai", page.activeProfile)
            var url = TimeTracker.resolveUrl(page.activeProfile)
            page.tracker.loadCustomers(url, token, function(customersResult) {
                var customers = customersResult.ok ? (customersResult.data || []) : []
                page.tracker.loadProjects(url, token, function(result) {
                    if (!result.ok) {
                        if (!hadCache) {
                            projectsStatus = i18n("Failed to load projects.")
                        }
                        page.loadingProjects = false
                        return
                    }
                    var projects = result.data || []
                    // Show the project list as soon as it arrives (flyout already has this).
                    page.applyCatalogEntities(customers, projects, page.allActivities)
                    function persist(activities) {
                        page.applyCatalogEntities(customers, projects, activities)
                        var prev = CatalogCache.load()
                        CatalogCache.store(page.activeProfile.id, {
                            customers: customers,
                            projects: projects,
                            activities: activities,
                            entityFingerprint: CatalogCache.entityFingerprint(
                                customers, projects, activities),
                            customerGroups: prev.customerGroups,
                            projectGroups: prev.projectGroups,
                            activityGroups: prev.activityGroups,
                            shiftedCount: prev.shiftedCount,
                            groupCount: prev.groupCount,
                            settingsKey: prev.settingsKey,
                            statusText: prev.statusText,
                            effectiveSimilarity: prev.effectiveSimilarity
                        })
                        Secret.saveCatalogCache(execSource, page.catalogCacheScript, CatalogCache.exportPayload())
                    }
                    if (typeof page.tracker.loadAllActivities === "function") {
                        // Prominent indicator in the empty activities pane:
                        // loadAllActivities fills page.allActivities for later "pinning",
                        // but we still need an explicit loading flag + status.
                        page.loadingActivities = true
                        page.activitiesStatus = i18n("Loading activities…")
                        page.tracker.loadAllActivities(url, token, function(actResult) {
                            persist(actResult.ok ? (actResult.data || []) : [])
                        })
                    } else {
                        persist(page.allActivities || [])
                    }
                })
            })
        })
    }

    function showActivitiesForProject(project) {
        if (!project) {
            return
        }
        page.loadingActivities = false
        selectedProject = project
        var cachedForProject = page.projectActivities[project.id]
            || page.projectActivities[String(project.id)]
        var source = cachedForProject || page.allActivities
        if (source && source.length) {
            page.activityRowModel = KimaiApi.activitiesListModel(source, project.id)
            var split = KimaiApi.splitActivitiesForProject(source, project.id)
            activitiesStatus = i18n("%1 project-specific, %2 global",
                                   split.projectSpecific.length, split.global.length)
            return
        }
        page.fetchActivitiesForProject(project)
    }

    function loadActivitiesForProject(project) {
        page.showActivitiesForProject(project)
    }

    function fetchActivitiesForProject(project) {
        page.loadingActivities = true
        activitiesStatus = i18n("Loading activities…")
        Secret.load(execSource, page.kwalletScript, page.activeProfile.id, function(token) {
            if (!token) {
                activitiesStatus = i18n("No API token available.")
                page.loadingActivities = false
                return
            }
            TimeTracker.applySession(page.activeProfile.provider || "kimai", page.activeProfile)
            page.tracker.loadActivities(TimeTracker.resolveUrl(page.activeProfile), token, project.id, function(result) {
                if (result.ok) {
                    var copy = {}
                    var key
                    for (key in page.projectActivities) {
                        if (page.projectActivities.hasOwnProperty(key)) {
                            copy[key] = page.projectActivities[key]
                        }
                    }
                    copy[project.id] = result.data || []
                    page.projectActivities = copy
                    page.activityRowModel = KimaiApi.activitiesListModel(result.data || [], project.id)
                    var split = KimaiApi.splitActivitiesForProject(result.data || [], project.id)
                    activitiesStatus = i18n("%1 project-specific, %2 global",
                                           split.projectSpecific.length, split.global.length)
                    page.loadingActivities = false
                } else {
                    activitiesStatus = i18n("Failed to load activities.")
                    page.loadingActivities = false
                }
            })
        })
    }

    function syncPinnedToCfg() {
        page.cfg_pinnedActivities = pinnedField.text
    }

    function toggleActivity(projectId, activityId) {
        var key = String(projectId) + ":" + String(activityId)
        var stamp = Date.now()
        if (page.lastToggleStamp[key] && stamp - page.lastToggleStamp[key] < 400) {
            return
        }
        page.lastToggleStamp[key] = stamp
        pinnedField.text = Favorites.togglePinned(pinnedField.text, projectId, activityId)
        syncPinnedToCfg()
        unsavedChanges = true
        configurationChanged()
    }

    property var lastToggleStamp: ({})

    function isSelected(projectId, activityId) {
        return Favorites.isPinned(pinnedField.text, projectId, activityId)
    }

    function sectionTitle(section) {
        if (section === "project") {
            return i18n("Project-specific")
        }
        if (section === "global") {
            return i18n("Global activities")
        }
        return section
    }

    function customerColorForSection(name) {
        for (var i = 0; i < projectRows.length; i++) {
            if (projectRows[i].customerName === name) {
                return projectRows[i].customerColor || KimaiApi.DEFAULT_CUSTOMER_COLOR
            }
        }
        return KimaiApi.DEFAULT_CUSTOMER_COLOR
    }

    function customerIdForSection(name) {
        for (var i = 0; i < projectRows.length; i++) {
            if (projectRows[i].customerName === name) {
                return projectRows[i].customerId !== undefined ? projectRows[i].customerId : null
            }
        }
        return null
    }

    RowLayout {
        anchors {
            fill: parent
            margins: page.pageMargin
        }
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: parent.width / 2
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 1
                text: i18n("Favorites")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: i18n("Projects")
                    font.bold: true
                }

                PlasmaComponents3.Button {
                    text: i18n("Reload")
                    icon.name: "view-refresh"
                    onClicked: {
                        page.beginLoadingUi()
                        page.loadProjects(true)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.BusyIndicator {
                    visible: page.loadingProjects
                    running: page.loadingProjects
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    Accessible.name: i18n("Loading projects")
                    Accessible.role: Accessible.Animation
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.75
                    text: page.projectsStatus
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                QQC2.ScrollView {
                    anchors.fill: parent
                    clip: true
                    visible: page.projectRows.length > 0 || !page.loadingProjects

                ListView {
                    id: projectsList
                    model: page.projectRows
                    section.property: "customerName"
                    section.criteria: ViewSection.FullString
                    section.delegate: Item {
                        width: ListView.view ? ListView.view.width : parent.width
                        height: Math.max(sectionRow.implicitHeight, Kirigami.Units.iconSizes.small * 0.85)
                                + Kirigami.Units.smallSpacing

                        ColorLabelRow {
                            id: sectionRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Kirigami.Units.smallSpacing
                            anchors.rightMargin: Kirigami.Units.smallSpacing
                            customerRole: true
                            customerColor: page.customerColorForSection(section)
                            colorCategory: "customer"
                            entityId: page.customerIdForSection(section)
                            label: section
                        }
                    }
                    delegate: QQC2.ItemDelegate {
                        width: ListView.view.width
                        leftPadding: Kirigami.Units.smallSpacing
                        rightPadding: Kirigami.Units.smallSpacing
                        topPadding: Kirigami.Units.smallSpacing / 2
                        bottomPadding: Kirigami.Units.smallSpacing / 2
                        spacing: 0
                        highlighted: page.selectedProject && page.selectedProject.id === modelData.project.id
                        onClicked: page.loadActivitiesForProject(modelData.project)

                        Accessible.name: modelData.project.name
                        Accessible.role: Accessible.ListItem
                        Accessible.onPressAction: page.loadActivitiesForProject(modelData.project)

                        contentItem: ColorLabelRow {
                            width: parent ? parent.width : implicitWidth
                            customerRole: false
                            customerColor: modelData.projectColor || modelData.customerColor || KimaiApi.DEFAULT_CUSTOMER_COLOR
                            colorCategory: modelData.colorCategory || ""
                            entityId: modelData.entityId !== undefined ? modelData.entityId : null
                            label: modelData.project.name
                            labelBold: false
                        }
                    }
                }
                }

                PlasmaComponents3.BusyIndicator {
                    anchors.centerIn: parent
                    visible: page.loadingProjects && page.projectRows.length === 0
                    running: visible
                    implicitWidth: Kirigami.Units.gridUnit * 2
                    implicitHeight: Kirigami.Units.gridUnit * 2
                    Accessible.name: i18n("Loading projects")
                    Accessible.role: Accessible.Animation
                }
            }
        }

        Kirigami.Separator {
            Layout.fillHeight: true
        }

        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: parent.width / 2
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: page.selectedProject
                      ? i18n("Activities — %1", page.selectedProject.name)
                      : i18n("Activities")
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.BusyIndicator {
                    visible: page.loadingActivities
                    running: page.loadingActivities
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.75
                    text: page.activitiesStatus
                }
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: activitiesList
                    model: page.activityRowModel
                    section.property: "section"
                    section.criteria: ViewSection.FullString
                    section.delegate: Kirigami.Heading {
                        width: ListView.view ? ListView.view.width : parent.width
                        level: 5
                        text: page.sectionTitle(section)
                        leftPadding: Kirigami.Units.smallSpacing
                        topPadding: Kirigami.Units.smallSpacing
                        bottomPadding: Kirigami.Units.smallSpacing / 2
                    }
                    delegate: QQC2.CheckDelegate {
                        width: ListView.view.width
                        text: modelData.activity.name
                        checked: page.selectedProject
                                   ? page.isSelected(page.selectedProject.id, modelData.activity.id)
                                   : false
                        function activateToggle() {
                            if (page.selectedProject) {
                                page.toggleActivity(page.selectedProject.id, modelData.activity.id)
                            }
                        }
                        onToggled: activateToggle()
                        Accessible.onPressAction: activateToggle()
                        Accessible.onToggleAction: activateToggle()
                    }
                }
            }
        }

        QQC2.TextField {
            id: pinnedField
            visible: false
        }
    }
}
