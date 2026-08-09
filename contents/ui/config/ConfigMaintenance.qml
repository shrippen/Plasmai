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

    function applyColorOptions() {
        ColorDistinct.configure(
            plasmoid.configuration.colorDistinctionEnabled !== false,
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
        ColorDistinct.rebuild(page.customers, page.projects, page.activities, true)
        page.customerGroups = ColorDistinct.maintenanceGroups("customer", page.customers)
        page.projectGroups = ColorDistinct.maintenanceGroups("project", page.projects)
        page.activityGroups = ColorDistinct.maintenanceGroups("activity", page.activities)
        page.groupCount = page.customerGroups.length + page.projectGroups.length + page.activityGroups.length
        page.shiftedCount = page.countShifted(page.customerGroups)
            + page.countShifted(page.projectGroups)
            + page.countShifted(page.activityGroups)
    }

    function loadCatalog() {
        if (!page.activeProfile || !page.activeProfile.url) {
            statusText = i18n("Configure a server URL on the Connection tab first.")
            return
        }
        statusText = i18n("Loading customers, projects, and activities…")
        Secret.load(execSource, page.kwalletScript, page.activeProfile.id, function(token, err) {
            if (err || !token) {
                statusText = i18n("Save an API token on the Connection tab first.")
                return
            }
            TimeTracker.applySession(page.activeProfile.provider || "kimai", page.activeProfile)
            var url = TimeTracker.resolveUrl(page.activeProfile)
            page.tracker.loadCustomers(url, token, function(customersResult) {
                page.customers = customersResult.ok ? (customersResult.data || []) : []
                page.tracker.loadProjects(url, token, function(projectsResult) {
                    page.projects = projectsResult.ok ? (projectsResult.data || []) : []
                    function finish(acts) {
                        page.activities = acts || []
                        page.rebuildRows()
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
                    if (typeof page.tracker.loadAllActivities === "function") {
                        page.tracker.loadAllActivities(url, token, function(actResult) {
                            finish(actResult.ok ? (actResult.data || []) : [])
                        })
                    } else {
                        finish([])
                    }
                })
            })
        })
    }

    Component.onCompleted: {
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
            }
            page.loadCatalog()
        })
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: page.pageMargin
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Only colors that clash within a category are listed. Each group starts with the entry that kept the Kimai color; shifted variants follow. Unique colors are hidden.")
        }

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Button {
                text: i18n("Reload from server")
                icon.name: "view-refresh"
                onClicked: page.loadCatalog()
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
