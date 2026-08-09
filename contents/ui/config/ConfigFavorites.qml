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
import ".."

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

    property alias cfg_pinnedActivities: pinnedField.text
    property var availableProjects: []
    property var projectRows: []
    property var projectActivities: ({})
    property var selectedProject: null
    property var activityRowModel: []
    property string projectsStatus: ""
    property string activitiesStatus: ""

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            Secret.handleData(execSource, sourceName, data)
        }
    }

    Component.onCompleted: {
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
                if (typeof shared.pinnedActivities === "string") {
                    pinnedField.text = shared.pinnedActivities
                }
            }
            loadProjects()
        })
    }

    function persistShared() {
        Secret.persistSharedPatch(execSource, page.sharedConfigScript, plasmoid.configuration, {
            pinnedActivities: pinnedField.text
        })
    }

    function loadProjects() {
        if (!page.activeProfile || !page.activeProfile.url) {
            projectsStatus = i18n("Configure a Kimai URL on the Connection tab first.")
            return
        }
        projectsStatus = i18n("Loading projects…")
        Secret.load(execSource, page.kwalletScript, page.activeProfile.id, function(token, err) {
            if (err || !token) {
                projectsStatus = i18n("Save an API token on the Connection tab first.")
                return
            }
            TimeTracker.applySession(page.activeProfile.provider || "kimai", page.activeProfile)
            page.tracker.loadCustomers(TimeTracker.resolveUrl(page.activeProfile), token, function(customersResult) {
                var customers = customersResult.ok ? (customersResult.data || []) : []
                page.tracker.loadProjects(TimeTracker.resolveUrl(page.activeProfile), token, function(result) {
                    if (result.ok) {
                        availableProjects = result.data || []
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
                            page.providerCapabilities.colorDistinction
                                && plasmoid.configuration.colorDistinctionEnabled !== false,
                            plasmoid.configuration.colorSimilarityPercent || 22
                        )
                        ColorDistinct.rebuild(customers, availableProjects, [], true)
                        projectRows = KimaiApi.projectsGroupedByCustomer(availableProjects, customers)
                        projectsStatus = i18n("Loaded %1 projects.", availableProjects.length)
                        selectedProject = null
                        activityRowModel = []
                        activitiesStatus = i18n("Select a project to pin activities.")
                    } else {
                        projectsStatus = i18n("Failed to load projects.")
                    }
                })
            })
        })
    }

    function loadActivitiesForProject(project) {
        if (!project) {
            return
        }
        selectedProject = project
        activitiesStatus = i18n("Loading activities…")
        Secret.load(execSource, page.kwalletScript, page.activeProfile.id, function(token) {
            if (!token) {
                activitiesStatus = i18n("No API token available.")
                return
            }
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
                } else {
                    activitiesStatus = i18n("Failed to load activities.")
                }
            })
        })
    }

    function toggleActivity(projectId, activityId) {
        pinnedField.text = Favorites.togglePinned(pinnedField.text, projectId, activityId)
        persistShared()
    }

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

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: i18n("Projects")
                font.bold: true
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.75
                text: page.projectsStatus
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

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

            PlasmaComponents3.Button {
                text: i18n("Reload")
                icon.name: "view-refresh"
                onClicked: page.loadProjects()
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

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.75
                text: page.activitiesStatus
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
                        onToggled: {
                            if (page.selectedProject) {
                                page.toggleActivity(page.selectedProject.id, modelData.activity.id)
                            }
                        }
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
