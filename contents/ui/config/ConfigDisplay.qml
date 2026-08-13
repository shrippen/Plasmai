import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import "../../code/secret.js" as Secret
import "../../code/sharedConfig.js" as SharedConfig
import "../../code/geocode.js" as Geocode
import "../../code/profiles.js" as Profiles
import "../../code/timeTracker.js" as TimeTracker

ConfigPage {
    id: page

    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/sharedConfig.sh"))
    readonly property int pageMargin: Kirigami.Units.gridUnit
    /** Stack FormLayout labels above fields when the config window is narrow. */
    readonly property bool formWide: scroll.availableWidth >= Kirigami.Units.gridUnit * 28
    readonly property int compactFieldWidth: Kirigami.Units.gridUnit * 8

    function buddyMaxWidth(form) {
        var formW = form && form.width > 0 ? form.width : scroll.availableWidth
        if (!page.formWide) {
            return Math.max(Kirigami.Units.gridUnit * 10, formW - page.pageMargin * 2)
        }
        // Leave room for the label column + margins.
        return Math.max(Kirigami.Units.gridUnit * 10, formW - Kirigami.Units.gridUnit * 14)
    }

    readonly property var activeProfile: Profiles.profileById(
        Profiles.parseProfiles(plasmoid.configuration.profilesJson, plasmoid.configuration.kimaiUrl),
        plasmoid.configuration.activeProfileId || "default"
    )
    readonly property var providerCapabilities: TimeTracker.providerCapabilities(
        activeProfile && activeProfile.provider ? activeProfile.provider : "kimai")
    readonly property bool supportsColorDistinction: providerCapabilities.colorDistinction

    property bool syncing: false
    property bool ready: false
    property bool geoSearching: false
    property var geoResults: []
    property string geoStatus: ""

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            Secret.handleData(execSource, sourceName, data)
        }
    }

    function formatCoord(value, digits) {
        var n = Number(value)
        if (isNaN(n)) {
            return ""
        }
        return n.toFixed(digits || 4)
    }

    function parseCoord(text, min, max, fallback) {
        var n = parseFloat(String(text).replace(",", "."))
        if (isNaN(n)) {
            return fallback
        }
        return Math.max(min, Math.min(max, n))
    }

    function syncLocationFields() {
        latitudeField.text = page.formatCoord(page.cfg_latitude, 4)
        longitudeField.text = page.formatCoord(page.cfg_longitude, 4)
    }

    function applyLocation(lat, lon, name) {
        page.cfg_latitude = lat
        page.cfg_longitude = lon
        page.cfg_locationName = name || ""
        page.syncLocationFields()
        page.persistShared()
    }

    function searchLocation() {
        var q = locationSearchField.text
        if (!String(q).trim()) {
            geoStatus = i18n("Enter a city or place name to search.")
            geoResults = []
            return
        }
        geoSearching = true
        geoStatus = i18n("Searching…")
        geoResults = []
        Geocode.search(q, function(result) {
            geoSearching = false
            if (!result.ok) {
                geoResults = []
                geoStatus = i18n("Location search failed. Check your network connection.")
                return
            }
            geoResults = result.results || []
            if (geoResults.length === 0) {
                geoStatus = i18n("No places found.")
            } else {
                geoStatus = i18np("%1 place found.", "%1 places found.", geoResults.length)
            }
        })
    }

    function displayPatch() {
        return {
            refreshInterval: refreshIntervalSpin.value,
            recentCount: recentCountSpin.value,
            useBlurBackground: useBlurBackgroundCheck.checked,
            workDayBegin: workDayBeginField.text,
            workDayEnd: workDayEndField.text,
            latitude: page.cfg_latitude,
            longitude: page.cfg_longitude,
            locationName: page.cfg_locationName,
            popupShowSparkline: popupSparklineCheck.checked,
            desktopShowSparkline: desktopSparklineCheck.checked,
            showSparklineArcs: sparklineArcsCheck.checked,
            showElapsedInPanel: panelElapsedCheck.checked,
            showProjectInPanel: panelProjectCheck.checked,
            showActivityInPanel: panelActivityCheck.checked,
            popupShowWorkSummary: popupWorkSummaryCheck.checked,
            popupShowFavorites: popupFavoritesCheck.checked,
            popupShowRecent: popupRecentCheck.checked,
            popupShowContinue: popupContinueCheck.checked,
            popupShowNewActivity: popupNewActivityCheck.checked,
            desktopShowWorkSummary: desktopWorkSummaryCheck.checked,
            desktopShowFavorites: desktopFavoritesCheck.checked,
            desktopShowRecent: desktopRecentCheck.checked,
            desktopShowNewActivity: desktopNewActivityCheck.checked,
            showFavorites: popupFavoritesCheck.checked || desktopFavoritesCheck.checked,
            colorDistinctionEnabled: colorDistinctionCheck.checked,
            colorSimilarityPercent: colorSimilaritySpin.value,
            touchMode: page.cfg_touchMode
        }
    }

    function syncControlsToCfg() {
        page.cfg_refreshInterval = refreshIntervalSpin.value
        page.cfg_recentCount = recentCountSpin.value
        page.cfg_useBlurBackground = useBlurBackgroundCheck.checked
        page.cfg_workDayBegin = workDayBeginField.text
        page.cfg_workDayEnd = workDayEndField.text
        page.cfg_popupShowSparkline = popupSparklineCheck.checked
        page.cfg_desktopShowSparkline = desktopSparklineCheck.checked
        page.cfg_showSparklineArcs = sparklineArcsCheck.checked
        page.cfg_showElapsedInPanel = panelElapsedCheck.checked
        page.cfg_showProjectInPanel = panelProjectCheck.checked
        page.cfg_showActivityInPanel = panelActivityCheck.checked
        page.cfg_popupShowWorkSummary = popupWorkSummaryCheck.checked
        page.cfg_popupShowFavorites = popupFavoritesCheck.checked
        page.cfg_popupShowRecent = popupRecentCheck.checked
        page.cfg_popupShowContinue = popupContinueCheck.checked
        page.cfg_popupShowNewActivity = popupNewActivityCheck.checked
        page.cfg_desktopShowWorkSummary = desktopWorkSummaryCheck.checked
        page.cfg_desktopShowFavorites = desktopFavoritesCheck.checked
        page.cfg_desktopShowRecent = desktopRecentCheck.checked
        page.cfg_desktopShowNewActivity = desktopNewActivityCheck.checked
        page.cfg_showFavorites = popupFavoritesCheck.checked || desktopFavoritesCheck.checked
        page.cfg_colorDistinctionEnabled = colorDistinctionCheck.checked
        page.cfg_colorSimilarityPercent = colorSimilaritySpin.value
        page.cfg_touchMode = touchModeCombo.currentIndex
    }

    function applyCfgToControls() {
        if (typeof page.cfg_refreshInterval === "number") {
            refreshIntervalSpin.value = page.cfg_refreshInterval
        }
        if (typeof page.cfg_recentCount === "number") {
            recentCountSpin.value = page.cfg_recentCount
        }
        useBlurBackgroundCheck.checked = !!page.cfg_useBlurBackground
        if (page.cfg_workDayBegin) {
            workDayBeginField.text = page.cfg_workDayBegin
        }
        if (page.cfg_workDayEnd) {
            workDayEndField.text = page.cfg_workDayEnd
        }
        popupSparklineCheck.checked = page.cfg_popupShowSparkline !== false
        desktopSparklineCheck.checked = page.cfg_desktopShowSparkline !== false
        sparklineArcsCheck.checked = page.cfg_showSparklineArcs !== false
        panelElapsedCheck.checked = page.cfg_showElapsedInPanel !== false
        panelProjectCheck.checked = page.cfg_showProjectInPanel !== false
        panelActivityCheck.checked = !!page.cfg_showActivityInPanel
        popupWorkSummaryCheck.checked = page.cfg_popupShowWorkSummary !== false
        popupFavoritesCheck.checked = page.cfg_popupShowFavorites !== false
        popupRecentCheck.checked = page.cfg_popupShowRecent !== false
        popupContinueCheck.checked = page.cfg_popupShowContinue !== false
        popupNewActivityCheck.checked = page.cfg_popupShowNewActivity !== false
        desktopWorkSummaryCheck.checked = page.cfg_desktopShowWorkSummary !== false
        desktopSparklineCheck.checked = page.cfg_desktopShowSparkline !== false
        desktopFavoritesCheck.checked = page.cfg_desktopShowFavorites !== false
        desktopRecentCheck.checked = page.cfg_desktopShowRecent !== false
        desktopNewActivityCheck.checked = page.cfg_desktopShowNewActivity !== false
        colorDistinctionCheck.checked = page.cfg_colorDistinctionEnabled !== false
        if (typeof page.cfg_colorSimilarityPercent === "number") {
            colorSimilaritySpin.value = page.cfg_colorSimilarityPercent
        }
        if (typeof page.cfg_touchMode === "number") {
            touchModeCombo.currentIndex = Math.max(0, Math.min(2, page.cfg_touchMode))
        }
        page.syncLocationFields()
    }

    function persistShared() {
        if (syncing || !ready) {
            return
        }
        page.syncControlsToCfg()
        Secret.persistSharedPatch(
            execSource, page.sharedConfigScript, plasmoid.configuration, page.displayPatch()
        )
    }

    function applyShared(shared) {
        if (!shared) {
            return
        }
        syncing = true
        SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
        if (typeof shared.refreshInterval === "number") {
            refreshIntervalSpin.value = shared.refreshInterval
        }
        if (typeof shared.recentCount === "number") {
            recentCountSpin.value = shared.recentCount
        }
        if (typeof shared.useBlurBackground === "boolean") {
            useBlurBackgroundCheck.checked = shared.useBlurBackground
        }
        if (typeof shared.workDayBegin === "string" && shared.workDayBegin.length > 0) {
            workDayBeginField.text = shared.workDayBegin
        }
        if (typeof shared.workDayEnd === "string" && shared.workDayEnd.length > 0) {
            workDayEndField.text = shared.workDayEnd
        }
        if (typeof shared.colorDistinctionEnabled === "boolean") {
            colorDistinctionCheck.checked = shared.colorDistinctionEnabled
        }
        if (typeof shared.colorSimilarityPercent === "number") {
            colorSimilaritySpin.value = shared.colorSimilarityPercent
        }
        if (typeof shared.touchMode === "number") {
            page.cfg_touchMode = Math.max(0, Math.min(2, shared.touchMode))
            touchModeCombo.currentIndex = page.cfg_touchMode
        }
        if (typeof shared.latitude === "number") {
            page.cfg_latitude = shared.latitude
        }
        if (typeof shared.longitude === "number") {
            page.cfg_longitude = shared.longitude
        }
        if (typeof shared.locationName === "string") {
            page.cfg_locationName = shared.locationName
        }
        if (typeof shared.popupShowSparkline === "boolean") {
            popupSparklineCheck.checked = shared.popupShowSparkline
        }
        if (typeof shared.desktopShowSparkline === "boolean") {
            desktopSparklineCheck.checked = shared.desktopShowSparkline
        }
        if (typeof shared.showSparklineArcs === "boolean") {
            sparklineArcsCheck.checked = shared.showSparklineArcs
        }
        if (typeof shared.showElapsedInPanel === "boolean") {
            panelElapsedCheck.checked = shared.showElapsedInPanel
        }
        if (typeof shared.showProjectInPanel === "boolean") {
            panelProjectCheck.checked = shared.showProjectInPanel
        }
        if (typeof shared.showActivityInPanel === "boolean") {
            panelActivityCheck.checked = shared.showActivityInPanel
        }
        if (typeof shared.popupShowWorkSummary === "boolean") {
            popupWorkSummaryCheck.checked = shared.popupShowWorkSummary
        }
        if (typeof shared.popupShowFavorites === "boolean") {
            popupFavoritesCheck.checked = shared.popupShowFavorites
        } else if (typeof shared.showFavorites === "boolean") {
            popupFavoritesCheck.checked = shared.showFavorites
        }
        if (typeof shared.popupShowRecent === "boolean") {
            popupRecentCheck.checked = shared.popupShowRecent
        }
        if (typeof shared.popupShowContinue === "boolean") {
            popupContinueCheck.checked = shared.popupShowContinue
        }
        if (typeof shared.popupShowNewActivity === "boolean") {
            popupNewActivityCheck.checked = shared.popupShowNewActivity
        }
        if (typeof shared.desktopShowWorkSummary === "boolean") {
            desktopWorkSummaryCheck.checked = shared.desktopShowWorkSummary
        }
        if (typeof shared.desktopShowFavorites === "boolean") {
            desktopFavoritesCheck.checked = shared.desktopShowFavorites
        } else if (typeof shared.showFavorites === "boolean") {
            desktopFavoritesCheck.checked = shared.showFavorites
        }
        if (typeof shared.desktopShowRecent === "boolean") {
            desktopRecentCheck.checked = shared.desktopShowRecent
        }
        if (typeof shared.desktopShowNewActivity === "boolean") {
            desktopNewActivityCheck.checked = shared.desktopShowNewActivity
        }
        page.syncLocationFields()
        page.syncControlsToCfg()
        syncing = false
    }

    Component.onDestruction: Secret.cancelAll(execSource)

    onPageEntered: {
        page.applyCfgToControls()
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            page.applyShared(shared)
            page.syncLocationFields()
            ready = true
        })
    }

    Connections {
        target: page
        function onCfg_touchModeChanged() {
            var idx = Math.max(0, Math.min(2, page.cfg_touchMode))
            if (touchModeCombo.currentIndex !== idx) {
                touchModeCombo.currentIndex = idx
            }
        }
    }

    QQC2.ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: scroll.availableWidth
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                Layout.topMargin: page.pageMargin
                level: 1
                text: i18n("Display")
                wrapMode: Text.WordWrap
            }

            Kirigami.FormLayout {
                id: displayForm
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                Layout.bottomMargin: page.pageMargin
                wideMode: page.formWide

                // —— Appearance ——
                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Appearance")
                    Kirigami.FormData.isSection: true
                }

                QQC2.CheckBox {
                    id: useBlurBackgroundCheck
                    Kirigami.FormData.label: i18n("Background:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Use desktop blur (translucent background)")
                    onCheckedChanged: page.persistShared()
                }

                QQC2.ComboBox {
                    id: touchModeCombo
                    Kirigami.FormData.label: i18n("Touch optimization:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    model: [
                        i18n("Automatic (follow Plasma tablet mode)"),
                        i18n("On"),
                        i18n("Off")
                    ]
                    Component.onCompleted: currentIndex = Math.max(0, Math.min(2, page.cfg_touchMode))
                    onActivated: function(index) {
                        if (page.cfg_touchMode !== index) {
                            page.cfg_touchMode = index
                        }
                        page.persistShared()
                    }
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: i18n("Larger tap targets for buttons, lists, pickers, and date/time controls.")
                }

                // —— Updates ——
                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Updates")
                    Kirigami.FormData.isSection: true
                }

                QQC2.SpinBox {
                    id: refreshIntervalSpin
                    Kirigami.FormData.label: i18n("Refresh interval (seconds):")
                    from: 10
                    to: 300
                    stepSize: 5
                    onValueChanged: page.persistShared()
                }

                // —— Colors ——
                Kirigami.Separator {
                    visible: page.supportsColorDistinction
                    Kirigami.FormData.label: i18n("Colors")
                    Kirigami.FormData.isSection: true
                }

                QQC2.CheckBox {
                    id: colorDistinctionCheck
                    Kirigami.FormData.label: i18n("Distinction:")
                    visible: page.supportsColorDistinction
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Make similar colors distinctive within each category")
                    onCheckedChanged: page.persistShared()
                }

                QQC2.SpinBox {
                    id: colorSimilaritySpin
                    Kirigami.FormData.label: i18n("Similarity threshold (%):")
                    visible: page.supportsColorDistinction
                    from: 12
                    to: 80
                    stepSize: 1
                    enabled: colorDistinctionCheck.checked
                    onValueChanged: page.persistShared()
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    visible: page.supportsColorDistinction
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.75
                    text: i18n("Higher similarity values treat more colors as too close. Clashing items get vivid, well-spaced replacement colors. See Maintenance for clash groups.")
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    visible: !page.supportsColorDistinction
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.75
                    text: i18n("Color distinction is available for Kimai profiles (per-customer / project / activity colors).")
                }

                // —— Work hours ——
                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Work hours")
                    Kirigami.FormData.isSection: true
                }

                QQC2.TextField {
                    id: workDayBeginField
                    Kirigami.FormData.label: i18n("Usual work day start:")
                    Layout.fillWidth: false
                    Layout.preferredWidth: page.compactFieldWidth
                    Layout.maximumWidth: page.compactFieldWidth
                    placeholderText: "08:00"
                    onTextChanged: page.cfg_workDayBegin = text
                    onEditingFinished: page.persistShared()
                }

                QQC2.TextField {
                    id: workDayEndField
                    Kirigami.FormData.label: i18n("Usual work day end:")
                    Layout.fillWidth: false
                    Layout.preferredWidth: page.compactFieldWidth
                    Layout.maximumWidth: page.compactFieldWidth
                    placeholderText: "18:00"
                    onTextChanged: page.cfg_workDayEnd = text
                    onEditingFinished: page.persistShared()
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: i18n("Used for the sparkline zoom and remaining-time in the work summary.")
                }

                // —— Day sparkline (arcs + location) ——
                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Day sparkline")
                    Kirigami.FormData.isSection: true
                }

                QQC2.CheckBox {
                    id: sparklineArcsCheck
                    Kirigami.FormData.label: i18n("Arcs:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Show sun, moon, and work arcs")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: i18n("Hide the whole sparkline under Panel flyout or Desktop widget below.")
                }

                RowLayout {
                    Kirigami.FormData.label: i18n("Find location:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.SearchField {
                        id: locationSearchField
                        Layout.fillWidth: true
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 6
                        placeholderText: i18n("City, region, or address…")
                        enabled: !page.geoSearching
                        onAccepted: page.searchLocation()
                    }

                    QQC2.Button {
                        Layout.preferredWidth: implicitWidth
                        text: page.geoSearching ? i18n("Searching…") : i18n("Search")
                        icon.name: "edit-find"
                        display: page.formWide
                                 ? QQC2.AbstractButton.TextBesideIcon
                                 : QQC2.AbstractButton.IconOnly
                        enabled: !page.geoSearching && locationSearchField.text.trim().length > 0
                        onClicked: page.searchLocation()
                        QQC2.ToolTip.visible: hovered && !page.formWide
                        QQC2.ToolTip.text: i18n("Search")
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    visible: page.geoStatus.length > 0
                    wrapMode: Text.WordWrap
                    opacity: 0.8
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: page.geoStatus
                }

                QQC2.ScrollView {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    Layout.preferredHeight: page.geoResults.length > 0
                        ? Math.min(Kirigami.Units.gridUnit * 8,
                                   Math.max(Kirigami.Units.gridUnit * 2.5,
                                            page.geoResults.length * Kirigami.Units.gridUnit * 2.2))
                        : 0
                    visible: page.geoResults.length > 0
                    clip: true

                    ListView {
                        model: page.geoResults
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        delegate: QQC2.ItemDelegate {
                            width: ListView.view.width
                            text: modelData.displayName
                            icon.name: "mark-location"
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Icon {
                                    source: "mark-location"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: modelData.displayName
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                }
                            }
                            onClicked: {
                                page.applyLocation(modelData.latitude, modelData.longitude, modelData.displayName)
                                page.geoResults = []
                                page.geoStatus = i18n("Using %1", modelData.displayName)
                                locationSearchField.text = modelData.displayName
                            }
                        }
                    }
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    visible: String(page.cfg_locationName || "").length > 0
                    wrapMode: Text.WordWrap
                    opacity: 0.85
                    text: i18n("Current place: %1", page.cfg_locationName)
                }

                QQC2.TextField {
                    id: latitudeField
                    Kirigami.FormData.label: i18n("Latitude:")
                    Layout.fillWidth: false
                    Layout.preferredWidth: page.compactFieldWidth
                    Layout.maximumWidth: page.compactFieldWidth
                    placeholderText: "52.5200"
                    onEditingFinished: {
                        page.cfg_latitude = page.parseCoord(text, -90, 90, page.cfg_latitude)
                        text = page.formatCoord(page.cfg_latitude, 4)
                        page.cfg_locationName = ""
                        page.persistShared()
                    }
                }

                QQC2.TextField {
                    id: longitudeField
                    Kirigami.FormData.label: i18n("Longitude:")
                    Layout.fillWidth: false
                    Layout.preferredWidth: page.compactFieldWidth
                    Layout.maximumWidth: page.compactFieldWidth
                    placeholderText: "13.4050"
                    onEditingFinished: {
                        page.cfg_longitude = page.parseCoord(text, -180, 180, page.cfg_longitude)
                        text = page.formatCoord(page.cfg_longitude, 4)
                        page.cfg_locationName = ""
                        page.persistShared()
                    }
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: i18n("Search a place or enter coordinates for sunrise/sunset coloring. Powered by OpenStreetMap Nominatim.")
                }

                // —— Panel ——
                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Panel (taskbar)")
                    Kirigami.FormData.isSection: true
                }

                QQC2.CheckBox {
                    id: panelElapsedCheck
                    Kirigami.FormData.label: i18n("Show:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Elapsed time")
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: panelProjectCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Project name")
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: panelActivityCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Activity name")
                    onCheckedChanged: page.persistShared()
                }

                // —— Panel flyout ——
                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Panel flyout")
                    Kirigami.FormData.isSection: true
                }

                QQC2.CheckBox {
                    id: popupWorkSummaryCheck
                    Kirigami.FormData.label: i18n("Show:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Work summary (today / week / remaining)")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: popupSparklineCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Day sparkline")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: popupFavoritesCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Favorites")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: popupRecentCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Recent list")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: popupContinueCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Continue last activity")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: popupNewActivityCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Start / switch activity controls")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }

                // —— Desktop widget ——
                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Desktop widget")
                    Kirigami.FormData.isSection: true
                }

                QQC2.CheckBox {
                    id: desktopWorkSummaryCheck
                    Kirigami.FormData.label: i18n("Show:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Work summary (today / week / remaining)")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: desktopSparklineCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Day sparkline")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: desktopFavoritesCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Favorites")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: desktopRecentCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("Recent list")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }
                QQC2.CheckBox {
                    id: desktopNewActivityCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    text: i18n("New activity picker")
                    checked: true
                    onCheckedChanged: page.persistShared()
                }

                // —— Recent list size (shared) ——
                Kirigami.Separator {
                    Kirigami.FormData.label: i18n("Recent list")
                    Kirigami.FormData.isSection: true
                }

                QQC2.SpinBox {
                    id: recentCountSpin
                    Kirigami.FormData.label: i18n("Activities shown:")
                    from: 3
                    to: 25
                    stepSize: 1
                    onValueChanged: page.persistShared()
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(displayForm)
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: i18n("Applies to both the panel flyout and the desktop widget.")
                }
            }
        }
    }
}
