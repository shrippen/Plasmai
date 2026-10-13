import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/profiles.js" as Profiles
import "../../code/favorites.js" as Favorites
import "../../code/sharedConfig.js" as SharedConfig
import ".."

ConfigPage {
    id: page

    readonly property int pageMargin: Kirigami.Units.gridUnit

    readonly property var activeProfile: Profiles.profileById(
        Profiles.parseProfiles(plasmoid.configuration.profilesJson, plasmoid.configuration.kimaiUrl),
        plasmoid.configuration.activeProfileId || "default"
    )

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

        session.connection.loadStored().then(function(shared) {
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

        var cached = session.catalog.cached(page.activeProfile ? page.activeProfile.id : "default")
        if (cached) {
            page.pendingCatalogPayload = cached
            page.catalogLoadDone = true
            page.tryFinishCatalogLoad()
        } else {
            session.catalog.loadFileText().then(function(text) {
                if (!text) {
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
        session.connection.loadStored().then(function(shared) {
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
        session.settings.set({ pinnedActivities: pinnedField.text }, plasmoid.configuration)
    }

    function persistFavoritesConfig() {
        syncPinnedToCfg()
        page.persistShared()
        unsavedChanges = false
    }

    property var saveConfig: persistFavoritesConfig

    function applyCatalogEntities(customers, projects, activities) {
        page.customers = customers || []
        page.availableProjects = projects || []
        page.allActivities = activities || []
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
    }

    function applyPayloadIfUsable(payload) {
        if (!payload || !(payload.projects || []).length) {
            return false
        }
        session.catalog.keep(payload)
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

        if (!forceRefresh && page.applyPayloadIfUsable(session.catalog.cached(profileId))) {
            afterCache(true)
            return
        }

        if (!forceRefresh) {
            projectsStatus = i18n("Loading projects…")
            page.loadingProjects = true
        }

        // Disk cache via shell (Qt blocks XMLHttpRequest on file://).
        session.catalog.loadFile().then(function(payload) {
            afterCache(page.applyPayloadIfUsable(payload))
        })
    }

    function fetchProjectsFromApi(hadCache) {
        if (!hadCache) {
            projectsStatus = i18n("Loading projects…")
            page.loadingProjects = true
        }
        const customers = []
        const projects = []
        session.catalog.fetchFor(page.activeProfile, {
            noToken: function() {
                if (!hadCache) {
                    projectsStatus = i18n("Save an API token on the Connection tab first.")
                }
                page.loadingProjects = false
            },
            failed: function() {
                if (!hadCache) {
                    projectsStatus = i18n("Failed to load projects.")
                }
                page.loadingProjects = false
            },
            // Show the project list as soon as it arrives (flyout already has this).
            projects: function(foundCustomers, foundProjects) {
                customers.push.apply(customers, foundCustomers)
                projects.push.apply(projects, foundProjects)
                page.applyCatalogEntities(customers, projects, page.allActivities)
            },
            // Prominent indicator in the empty activities pane:
            // loadAllActivities fills page.allActivities for later "pinning",
            // but we still need an explicit loading flag + status.
            activitiesLoading: function() {
                page.loadingActivities = true
                page.activitiesStatus = i18n("Loading activities…")
            },
            activities: function(list) {
                page.applyCatalogEntities(customers, projects, list === null ? (page.allActivities || []) : list)
            }
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
        session.catalog.activitiesFor(page.activeProfile, project.id, function(result) {
            if (!result) {
                activitiesStatus = i18n("No API token available.")
                page.loadingActivities = false
                return
            }
            if (!result.ok) {
                activitiesStatus = i18n("Failed to load activities.")
                page.loadingActivities = false
                return
            }
            const copy = Object.assign({}, page.projectActivities)
            copy[project.id] = result.data || []
            page.projectActivities = copy
            page.activityRowModel = KimaiApi.activitiesListModel(result.data || [], project.id)
            const split = KimaiApi.splitActivitiesForProject(result.data || [], project.id)
            activitiesStatus = i18n("%1 project-specific, %2 global",
                                   split.projectSpecific.length, split.global.length)
            page.loadingActivities = false
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
