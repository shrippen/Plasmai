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
import ".."

ConfigPage {
    id: page

    readonly property string kwalletScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/kwallet.sh"))
    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/sharedConfig.sh"))
    readonly property int pageMargin: Kirigami.Units.gridUnit
    readonly property bool formWide: scroll.availableWidth >= Kirigami.Units.gridUnit * 28

    function buddyMaxWidth(form) {
        var formW = form && form.width > 0 ? form.width : scroll.availableWidth
        if (!page.formWide) {
            return Math.max(Kirigami.Units.gridUnit * 10, formW - page.pageMargin * 2)
        }
        return Math.max(Kirigami.Units.gridUnit * 10, formW - Kirigami.Units.gridUnit * 14)
    }

    property var profiles: Profiles.parseProfiles(profilesField.text, kimaiUrlField.text)
    property int selectedIndex: 0
    property bool updatingFields: false
    property bool syncing: false

    property string statusMessage: ""
    property bool statusIsError: false
    property bool busy: false
    property bool testingConnection: false
    property bool hasStoredToken: false

    function checkStoredToken() {
        if (profiles.length === 0 || selectedIndex < 0) {
            hasStoredToken = false
            return
        }
        var profileId = profiles[selectedIndex].id
        Secret.load(execSource, page.kwalletScript, profileId, function(token) {
            hasStoredToken = !!(token && token.length > 0)
        })
    }

    readonly property var selectedProfile: (profiles.length > 0 && selectedIndex >= 0 && selectedIndex < profiles.length)
        ? profiles[selectedIndex] : null
    readonly property string selectedProviderId: selectedProfile && selectedProfile.provider
        ? selectedProfile.provider : "kimai"
    readonly property var selectedProviderMeta: TimeTracker.providerMeta(selectedProviderId)
    readonly property var tracker: TimeTracker.api(selectedProviderId)

    /** i18n UI strings that follow the selected service. */
    readonly property string providerHintText: {
        switch (selectedProviderId) {
        case "clockify":
            return i18n("Clockify cloud API is prefilled. Change only for a regional endpoint (e.g. euc1).")
        case "toggl":
            return i18n("Toggl Track cloud API is prefilled. Use your personal API token from Profile settings.")
        case "solidtime":
            return i18n("SolidTime cloud API is prefilled. For self-hosting, replace with your instance base URL.")
        case "kimai":
        default:
            return i18n("Self-hosted Kimai or the official hosted service (kimai.cloud). Paste the instance URL.")
        }
    }
    readonly property string urlFieldLabel: selectedProviderMeta && !selectedProviderMeta.needsUrl
        ? i18n("API URL:")
        : i18n("Server URL:")
    readonly property string urlPlaceholderText: {
        switch (selectedProviderId) {
        case "clockify":
            return "https://api.clockify.me/api/v1"
        case "toggl":
            return "https://api.track.toggl.com/api/v9"
        case "solidtime":
            return i18n("https://api.solidtime.io or https://time.example.com")
        case "kimai":
        default:
            return i18n("https://kimai.example.com or https://www.kimai.cloud")
        }
    }
    readonly property string authFieldLabel: {
        switch (selectedProviderId) {
        case "clockify":
            return i18n("API key:")
        default:
            return i18n("API token:")
        }
    }

    function showStatus(msg, isError) {
        statusMessage = msg
        statusIsError = !!isError
    }

    function syncProfiles() {
        if (syncing) {
            return
        }
        syncing = true
        profilesField.text = Profiles.serializeProfiles(profiles)
        syncing = false
        persistShared()
    }

    function persistShared() {
        Secret.persistSharedPatch(execSource, page.sharedConfigScript, plasmoid.configuration, page.connectionPatch())
    }

    function connectionPatch() {
        var patch = {
            kimaiUrl: KimaiApi.normalizeUrl(kimaiUrlField.text),
            activeProfileId: activeProfileField.text || "default"
        }
        // Avoid persisting an empty profilesJson while reloading between KCM pages;
        // otherwise it can overwrite shared.json and force a default-only profile list.
        if (typeof profilesField.text === "string" && profilesField.text.length > 0) {
            patch.profilesJson = profilesField.text
        }
        return patch
    }

    function syncConnectionToCfg() {
        page.cfg_kimaiUrl = KimaiApi.normalizeUrl(kimaiUrlField.text)
        page.cfg_profilesJson = profilesField.text
        page.cfg_activeProfileId = activeProfileField.text || "default"
    }

    function persistConnectionConfig() {
        page.commitUrlField()
        page.syncConnectionToCfg()
        page.persistShared()
        unsavedChanges = false
    }

    property var saveConfig: persistConnectionConfig

    function notifyEdited() {
        if (syncing) return
        unsavedChanges = true
        configurationChanged()
    }

    function ensureSelection() {
        if (profiles.length === 0) {
            profiles = Profiles.defaultProfiles()
            if (kimaiUrlField.text) {
                profiles[0].url = KimaiApi.normalizeUrl(kimaiUrlField.text)
            }
            syncProfiles()
        }

        var activeIdx = 0
        for (var i = 0; i < profiles.length; i++) {
            if (profiles[i].id === activeProfileField.text) {
                activeIdx = i
                break
            }
        }
        selectedIndex = activeIdx
        profileCombo.currentIndex = activeIdx
        updateFieldsForSelection()
    }

    function updateFieldsForSelection() {
        if (profiles.length === 0 || selectedIndex < 0) {
            return
        }
        updatingFields = true
        profileNameField.text = profiles[selectedIndex].name
        kimaiUrlField.text = profiles[selectedIndex].url || ""
        var pid = profiles[selectedIndex].provider || "kimai"
        var ids = TimeTracker.providerIds()
        var pIdx = ids.indexOf(pid)
        providerCombo.currentIndex = pIdx >= 0 ? pIdx : 0
        updatingFields = false
    }

    function updateSelectedProfile(field, value) {
        if (updatingFields || syncing || profiles.length === 0 || selectedIndex < 0) {
            return
        }
        var copy = profiles.slice()
        var row = Object.assign({}, copy[selectedIndex])
        row[field] = value
        copy[selectedIndex] = row
        profiles = copy
        syncProfiles()
    }

    /**
     * Switch service: clear URL + session ids, then prefill defaults for
     * Clockify / Toggl / SolidTime. Kimai stays empty with a helpful placeholder.
     */
    function applyProviderChange(providerId) {
        if (updatingFields || syncing || profiles.length === 0 || selectedIndex < 0) {
            return
        }
        var meta = TimeTracker.providerMeta(providerId)
        var url = meta.defaultUrl || ""
        var copy = profiles.slice()
        var row = Object.assign({}, copy[selectedIndex])
        row.provider = providerId
        row.url = url
        row.workspaceId = ""
        row.userId = ""
        row.organizationId = ""
        row.memberId = ""
        copy[selectedIndex] = row
        profiles = copy
        syncProfiles()

        updatingFields = true
        kimaiUrlField.text = url
        updatingFields = false
        showStatus("", false)
    }

    function commitUrlField() {
        if (updatingFields || syncing || profiles.length === 0 || selectedIndex < 0) {
            return
        }
        var normalized = KimaiApi.normalizeUrl(kimaiUrlField.text)
        updateSelectedProfile("url", normalized)
        if (kimaiUrlField.text !== normalized) {
            updatingFields = true
            kimaiUrlField.text = normalized
            updatingFields = false
        }
    }

    function setActiveProfile() {
        if (profiles.length === 0 || selectedIndex < 0) {
            return
        }
        commitUrlField()
        activeProfileField.text = profiles[selectedIndex].id
        updatingFields = true
        kimaiUrlField.text = profiles[selectedIndex].url || ""
        updatingFields = false
        persistShared()
    }

    function applyTestConnectionMeta(data) {
        if (!data || profiles.length === 0 || selectedIndex < 0) {
            return
        }
        var copy = profiles.slice()
        var p = copy[selectedIndex]
        if (data.workspaceId) {
            p.workspaceId = data.workspaceId
        }
        if (data.userId) {
            p.userId = data.userId
        }
        if (data.organizationId) {
            p.organizationId = data.organizationId
        }
        if (data.memberId) {
            p.memberId = data.memberId
        }
        copy[selectedIndex] = p
        profiles = copy
        syncProfiles()
        notifyEdited()
    }

    function reloadConnectionState() {
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            page.syncing = true
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
            }
            // KCM cfg_* may be stale placeholders after visiting other tabs.
            // Seed resolve input from shared.json before ensureSelection/syncProfiles.
            var cfgConnection = {
                kimaiUrl: page.cfg_kimaiUrl,
                profilesJson: page.cfg_profilesJson,
                activeProfileId: page.cfg_activeProfileId
            }
            if (shared) {
                if (typeof shared.profilesJson === "string" && shared.profilesJson.length > 0) {
                    cfgConnection.profilesJson = shared.profilesJson
                }
                if (typeof shared.activeProfileId === "string" && shared.activeProfileId.length > 0) {
                    cfgConnection.activeProfileId = shared.activeProfileId
                }
                if (typeof shared.kimaiUrl === "string" && shared.kimaiUrl.length > 0) {
                    cfgConnection.kimaiUrl = shared.kimaiUrl
                }
            }
            var resolved = SharedConfig.resolveConnectionState(
                cfgConnection, shared, plasmoid.configuration)
            kimaiUrlField.text = resolved.kimaiUrl
            profilesField.text = resolved.profilesJson
            activeProfileField.text = resolved.activeProfileId
            page.syncing = false
            if (!profilesField.text && kimaiUrlField.text) {
                profiles = Profiles.parseProfiles("", kimaiUrlField.text)
                syncProfiles()
            } else {
                profiles = Profiles.parseProfiles(profilesField.text, kimaiUrlField.text)
            }
            if (!activeProfileField.text) {
                activeProfileField.text = "default"
            }
            syncConnectionToCfg()
            ensureSelection()
            checkStoredToken()
            unsavedChanges = false
        })
    }

    property bool reloadScheduled: false

    function scheduleConnectionReload() {
        if (reloadScheduled) {
            return
        }
        reloadScheduled = true
        Qt.callLater(function() {
            reloadScheduled = false
            if (!page.visible) {
                return
            }
            page.reloadConnectionState()
        })
    }

    Component.onDestruction: Secret.cancelAll(execSource)

    onVisibleChanged: if (visible) scheduleConnectionReload()
    onPageEntered: scheduleConnectionReload()

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            Secret.handleData(execSource, sourceName, data)
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
                text: i18n("Connection")
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                wrapMode: Text.WordWrap
                opacity: 0.8
                text: i18n("Configure a time-tracking profile. Choose Kimai, Clockify, Toggl Track, or SolidTime.")
            }

            Kirigami.FormLayout {
                id: connectionForm
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                wideMode: page.formWide

                QQC2.ComboBox {
                    id: profileCombo
                    Kirigami.FormData.label: i18n("Profile:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    model: page.profiles.map(function(p) { return p.name })
                    currentIndex: page.selectedIndex
                    onActivated: function(index) {
                        page.selectedIndex = index
                        page.updateFieldsForSelection()
                        page.checkStoredToken()
                    }
                }

                QQC2.TextField {
                    id: profileNameField
                    Kirigami.FormData.label: i18n("Profile name:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    onTextChanged: {
                        if (page.updatingFields) return
                        var trimmed = text.trim()
                        for (var i = 0; i < page.profiles.length; i++) {
                            if (i !== page.selectedIndex && page.profiles[i].name === trimmed) {
                                page.showStatus(i18n("A profile named \"%1\" already exists.", trimmed), true)
                                return
                            }
                        }
                        page.showStatus("", false)
                        page.updateSelectedProfile("name", text)
                        page.notifyEdited()
                    }
                }

                QQC2.ComboBox {
                    id: providerCombo
                    Kirigami.FormData.label: i18n("Service:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    model: TimeTracker.providerNames()
                    onActivated: function(index) {
                        if (page.updatingFields) {
                            return
                        }
                        page.applyProviderChange(TimeTracker.providerIds()[index])
                        page.notifyEdited()
                    }
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignLeft
                    color: Kirigami.Theme.neutralTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: page.providerHintText
                }

                QQC2.TextField {
                    id: kimaiUrlField
                    Kirigami.FormData.label: page.urlFieldLabel
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    placeholderText: page.urlPlaceholderText
                    onTextChanged: {
                        page.cfg_kimaiUrl = text
                        if (!page.updatingFields && !page.syncing) {
                            page.updateSelectedProfile("url", text)
                            page.notifyEdited()
                        }
                    }
                    onEditingFinished: page.commitUrlField()
                }

                QQC2.TextField {
                    id: tokenField
                    Kirigami.FormData.label: page.authFieldLabel
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    echoMode: TextInput.Password
                    placeholderText: i18n("Paste token to save in KWallet")
                    enabled: !page.busy
                }

                Flow {
                    id: profileActionsFlow
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    Layout.preferredHeight: implicitHeight
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Button {
                        text: i18n("Add profile")
                        icon.name: "list-add"
                        onClicked: {
                            var copy = page.profiles.slice()
                            var existingNames = {}
                            for (var n = 0; n < copy.length; n++) {
                                existingNames[copy[n].name] = true
                            }
                            var num = copy.length + 1
                            while (existingNames[i18n("Profile %1", num)]) {
                                num++
                            }
                            var profile = Profiles.normalizeProfile({
                                id: Profiles.newProfileId(),
                                name: i18n("Profile %1", num),
                                url: "",
                                provider: "kimai"
                            })
                            copy.push(profile)
                            page.profiles = copy
                            page.syncProfiles()
                            page.selectedIndex = copy.length - 1
                            profileCombo.currentIndex = page.selectedIndex
                            page.updateFieldsForSelection()
                            page.notifyEdited()
                        }
                    }
                    PlasmaComponents3.Button {
                        text: i18n("Remove")
                        icon.name: "list-remove"
                        enabled: page.profiles.length > 1
                        onClicked: {
                            if (page.profiles.length <= 1) {
                                return
                            }
                            var removedId = page.profiles[page.selectedIndex].id
                            var copy = page.profiles.slice()
                            copy.splice(page.selectedIndex, 1)
                            page.profiles = copy
                            page.syncProfiles()
                            page.selectedIndex = Math.max(0, page.selectedIndex - 1)
                            profileCombo.currentIndex = page.selectedIndex
                            page.updateFieldsForSelection()
                            if (activeProfileField.text === removedId) {
                                page.setActiveProfile()
                            }
                            page.notifyEdited()
                        }
                    }
                    PlasmaComponents3.Button {
                        text: i18n("Use this profile")
                        icon.name: "emblem-default"
                        enabled: page.profiles.length > 0
                        onClicked: { page.setActiveProfile(); page.notifyEdited() }
                    }
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.75
                    text: {
                        var active = Profiles.profileById(page.profiles, activeProfileField.text || "default")
                        return i18n("Active profile: %1", active ? active.name : i18n("none"))
                    }
                }

                Flow {
                    id: tokenActionsFlow
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    Layout.preferredHeight: implicitHeight
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Button {
                        text: page.busy ? i18n("Saving…") : i18n("Save token")
                        icon.name: "document-save"
                        enabled: !page.busy && tokenField.text.length > 0 && page.profiles.length > 0
                        onClicked: {
                            page.busy = true
                            page.showStatus("", false)
                            page.commitUrlField()
                            page.setActiveProfile()
                            var profileId = page.profiles[page.selectedIndex].id
                            Secret.save(execSource, page.kwalletScript, profileId, tokenField.text, function(ok, err) {
                                page.busy = false
                                if (ok) {
                                    tokenField.text = ""
                                    page.hasStoredToken = true
                                    page.showStatus(i18n("Token saved to KWallet for this profile."), false)
                                } else {
                                    page.showStatus(err || i18n("Failed to save token"), true)
                                }
                            })
                        }
                    }
                    PlasmaComponents3.Button {
                        text: i18n("Clear token")
                        icon.name: "edit-delete"
                        enabled: !page.busy && page.profiles.length > 0 && page.hasStoredToken
                        onClicked: {
                            page.busy = true
                            page.showStatus("", false)
                            var profileId = page.profiles[page.selectedIndex].id
                            Secret.clear(execSource, page.kwalletScript, profileId, function(ok, err) {
                                page.busy = false
                                if (ok) {
                                    page.hasStoredToken = false
                                    page.showStatus(i18n("Token removed from KWallet."), false)
                                } else {
                                    page.showStatus(err || i18n("Failed to clear token"), true)
                                }
                            })
                        }
                    }
                    PlasmaComponents3.Button {
                        text: i18n("Test connection")
                        icon.name: "network-connect"
                        enabled: !page.testingConnection && !page.busy && page.profiles.length > 0
                        onClicked: {
                            page.testingConnection = true
                            page.showStatus(i18n("Testing connection…"), false)
                            page.commitUrlField()
                            var profile = page.profiles[page.selectedIndex]
                            var profileId = profile.id
                            var url = TimeTracker.resolveUrl(profile)
                            TimeTracker.applySession(profile.provider || "kimai", profile)
                            Secret.load(execSource, page.kwalletScript, profileId, function(token, loadErr) {
                                if (loadErr) {
                                    page.testingConnection = false
                                    page.showStatus(loadErr, true)
                                    return
                                }
                                if (!token) {
                                    page.testingConnection = false
                                    page.showStatus(i18n("No API token stored. Save a token first."), true)
                                    return
                                }
                                page.tracker.testConnection(url, token, function(result) {
                                    page.testingConnection = false
                                    if (result.ok) {
                                        page.applyTestConnectionMeta(result.data)
                                        var label = TimeTracker.providerDisplayName(profile.provider)
                                        var ver = (result.data && (result.data.version || result.data.name)) || i18n("ok")
                                        page.showStatus(i18n("Connected to %1 (%2).", label, ver), false)
                                    } else {
                                        page.showStatus(ApiErrors.text(result.error, true), true)
                                    }
                                })
                            })
                        }
                    }
                }

                PlasmaComponents3.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(connectionForm)
                    Layout.bottomMargin: page.pageMargin
                    wrapMode: Text.WordWrap
                    visible: page.statusMessage.length > 0
                    color: page.statusIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
                    text: page.statusMessage
                }
            }

            QQC2.TextField {
                id: profilesField
                visible: false
                onTextChanged: page.cfg_profilesJson = text
            }
            QQC2.TextField {
                id: activeProfileField
                visible: false
                onTextChanged: page.cfg_activeProfileId = text
            }
        }
    }
}
