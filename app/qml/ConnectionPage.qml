import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/platform.js" as Platform
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/profiles.js" as Profiles
import "../contents/code/kimaiApi.js" as KimaiApi

Kirigami.Page {
    id: page
    title: i18n("Connection")

    property var profiles: []
    property int selectedIndex: 0
    property bool busy: false
    property bool hasStoredToken: false
    property string statusMessage: ""
    property bool statusIsError: false
    property bool syncing: false
    property bool updatingFields: false

    readonly property var selectedProfile: (profiles.length > 0 && selectedIndex >= 0 && selectedIndex < profiles.length)
        ? profiles[selectedIndex] : null
    readonly property string selectedProviderId: selectedProfile && selectedProfile.provider
        ? selectedProfile.provider : "kimai"
    readonly property var selectedProviderMeta: TimeTracker.providerMeta(selectedProviderId)
    readonly property var tracker: TimeTracker.api(selectedProviderId)

    function showStatus(msg, isError) {
        statusMessage = msg
        statusIsError = isError
    }

    // ── Profile management ──

    function syncProfiles() {
        if (syncing) return
        syncing = true
        profilesField.text = Profiles.serializeProfiles(profiles)
        syncing = false
    }

    function parseProfiles() {
        profiles = Profiles.parseProfiles(profilesField.text, urlField.text)
        ensureSelection()
    }

    function ensureSelection() {
        if (profiles.length === 0) {
            profiles = Profiles.defaultProfiles()
            if (urlField.text) {
                profiles[0].url = KimaiApi.normalizeUrl(urlField.text)
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
        if (profiles.length === 0 || selectedIndex < 0) return
        updatingFields = true
        profileNameField.text = profiles[selectedIndex].name
        urlField.text = profiles[selectedIndex].url || ""
        var pid = profiles[selectedIndex].provider || "kimai"
        var ids = ["kimai", "clockify", "toggl", "solidtime"]
        var pIdx = ids.indexOf(pid)
        providerCombo.currentIndex = pIdx >= 0 ? pIdx : 0
        updatingFields = false
    }

    function updateSelectedProfile(field, value) {
        if (updatingFields || syncing || profiles.length === 0 || selectedIndex < 0) return
        var copy = profiles.slice()
        var row = Object.assign({}, copy[selectedIndex])
        row[field] = value
        copy[selectedIndex] = row
        profiles = copy
        syncProfiles()
    }

    function setActiveProfile() {
        if (profiles.length === 0 || selectedIndex < 0) return
        commitUrlField()
        activeProfileField.text = profiles[selectedIndex].id
        updatingFields = true
        urlField.text = profiles[selectedIndex].url || ""
        updatingFields = false
        persistShared()
        // Live-apply the newly active profile so the timer view doesn't need
        // an app restart to notice (root only reads shared.json at startup
        // otherwise).
        root.loadSharedAndConnect()
    }

    function commitUrlField() {
        if (updatingFields || syncing || profiles.length === 0 || selectedIndex < 0) return
        var normalized = KimaiApi.normalizeUrl(urlField.text)
        updateSelectedProfile("url", normalized)
        if (urlField.text !== normalized) {
            updatingFields = true
            urlField.text = normalized
            updatingFields = false
        }
    }

    // ── Persistence ──

    function checkStoredToken() {
        if (profiles.length === 0 || selectedIndex < 0) {
            hasStoredToken = false
            return
        }
        Platform.loadToken(null, profiles[selectedIndex].id).then(function(token) {
            hasStoredToken = !!(token && token.length > 0)
        })
    }

    function persistShared() {
        var base = { kimaiUrl: urlField.text.trim(), profilesJson: profilesField.text, activeProfileId: activeProfileField.text || "default" }
        Platform.patchShared(null, base, base)
    }

    function loadSharedState() {
        Platform.loadShared(null).then(function(shared) {
            if (!shared) return
            syncing = true
            urlField.text = shared.kimaiUrl || ""
            profilesField.text = shared.profilesJson || ""
            activeProfileField.text = shared.activeProfileId || "default"
            syncing = false
            // Migrate: fill empty profile URLs from legacy kimaiUrl
            var parsed = Profiles.parseProfiles(profilesField.text, urlField.text)
            if (urlField.text && parsed.length > 0) {
                var changed = false
                for (var i = 0; i < parsed.length; i++) {
                    if (!parsed[i].url) {
                        parsed[i] = Object.assign({}, parsed[i], { url: urlField.text })
                        changed = true
                    }
                }
                if (changed) {
                    profiles = parsed
                    syncProfiles()
                }
            }
            parseProfiles()
            checkStoredToken()
        })
    }

    // Auto-scroll when the on-screen keyboard appears, so the focused
    // input field is not hidden behind it.
    Connections {
        target: Qt.inputMethod
        function onKeyboardRectangleChanged() {
            keyboardScrollTimer.restart()
        }
    }

    // Wait until the window has resized for the keyboard before scrolling the field into view.
    Timer {
        id: keyboardScrollTimer
        interval: 250
        onTriggered: page.ensureFocusedVisible()
    }

    function ensureFocusedVisible() {
        var fi = root.activeFocusItem
        var flick = pageScroll.contentItem
        if (!fi || !flick || Qt.inputMethod.keyboardRectangle.height <= 0) return
        var pos = flick.mapFromItem(fi, 0, 0)
        // pos is relative to the viewport, not to the scrolled content; the window already resizes for the keyboard.
        var overflow = pos.y + fi.height + Kirigami.Units.largeSpacing - flick.height
        if (overflow > 0) flick.contentY += overflow
        else if (pos.y < 0) flick.contentY += pos.y - Kirigami.Units.largeSpacing
    }

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: formCol
            width: pageScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            Kirigami.FormLayout {
                Layout.fillWidth: true
                wideMode: formCol.width >= Kirigami.Units.gridUnit * 28

                // ── Profile selector ──
                QQC2.ComboBox {
                    id: profileCombo
                    Kirigami.FormData.label: i18n("Profile:")
                    Layout.fillWidth: true
                    model: page.profiles.map(function(p) { return p.name })
                    currentIndex: page.selectedIndex
                    onActivated: function(index) {
                        if (page.updatingFields) return
                        page.selectedIndex = index
                        page.updateFieldsForSelection()
                        page.checkStoredToken()
                    }
                }

                QQC2.TextField {
                    id: profileNameField
                    Kirigami.FormData.label: i18n("Profile name:")
                    Layout.fillWidth: true
                    onEditingFinished: {
                        if (!page.updatingFields) {
                            page.updateSelectedProfile("name", text)
                            var idx = page.selectedIndex
                            page.profiles = page.profiles.slice()
                            profileCombo.currentIndex = idx
                        }
                    }
                }

                RowLayout {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Button {
                        text: i18n("Add")
                        icon.name: "list-add"
                        onClicked: {
                            var copy = page.profiles.slice()
                            var existingNames = {}
                            for (var n = 0; n < copy.length; n++) existingNames[copy[n].name] = true
                            var num = copy.length + 1
                            while (existingNames[i18n("Profile %1", num)]) num++
                            var profile = Profiles.normalizeProfile({
                                id: Profiles.newProfileId(),
                                name: i18n("Profile %1", num),
                                url: "",
                                provider: page.selectedProviderId || "kimai"
                            })
                            copy.push(profile)
                            page.profiles = copy
                            page.syncProfiles()
                            page.selectedIndex = copy.length - 1
                            profileCombo.currentIndex = page.selectedIndex
                            page.updateFieldsForSelection()
                            page.checkStoredToken()
                            page.persistShared()
                        }
                    }

                    QQC2.Button {
                        text: i18n("Remove")
                        icon.name: "list-remove"
                        enabled: page.profiles.length > 1
                        onClicked: {
                            if (page.profiles.length <= 1) return
                            var removedId = page.profiles[page.selectedIndex].id
                            var copy = page.profiles.slice()
                            copy.splice(page.selectedIndex, 1)
                            page.profiles = copy
                            page.syncProfiles()
                            page.selectedIndex = Math.max(0, page.selectedIndex - 1)
                            profileCombo.currentIndex = page.selectedIndex
                            page.updateFieldsForSelection()
                            if (activeProfileField.text === removedId) page.setActiveProfile()
                            page.checkStoredToken()
                            page.persistShared()
                        }
                    }

                    QQC2.Button {
                        text: i18n("Use this")
                        icon.name: "emblem-default"
                        enabled: page.profiles.length > 0
                        onClicked: { page.setActiveProfile(); page.checkStoredToken() }
                    }
                }

                QQC2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    text: {
                        var active = Profiles.profileById(page.profiles, activeProfileField.text || "default")
                        return i18n("Active: %1", active ? active.name : i18n("none"))
                    }
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                Kirigami.Separator { Kirigami.FormData.isSection: true; Layout.fillWidth: true }

                // ── Provider ──
                QQC2.ComboBox {
                    id: providerCombo
                    Kirigami.FormData.label: i18n("Provider:")
                    Layout.fillWidth: true
                    model: ["Kimai", "Clockify", "Toggl Track", "SolidTime"]
                    currentIndex: {
                        var id = page.selectedProviderId
                        if (id === "clockify") return 1
                        if (id === "toggl") return 2
                        if (id === "solidtime") return 3
                        return 0
                    }
                    onCurrentIndexChanged: {
                        if (page.updatingFields || page.syncing) return
                        var ids = ["kimai", "clockify", "toggl", "solidtime"]
                        var defaults = {
                            kimai: "",
                            clockify: "https://api.clockify.me/api/v1",
                            toggl: "https://api.track.toggl.com/api/v9",
                            solidtime: "https://api.solidtime.io"
                        }
                        var newId = ids[currentIndex] || "kimai"
                        urlField.placeholderText = defaults[newId] || ""
                        page.updateSelectedProfile("provider", newId)
                        page.updateFieldsForSelection()
                    }
                }

                QQC2.TextField {
                    id: urlField
                    Kirigami.FormData.label: i18n("Server URL:")
                    Layout.fillWidth: true
                    placeholderText: i18n("https://your-server.com")
                    onTextChanged: {
                        if (!page.updatingFields && !page.syncing) page.updateSelectedProfile("url", text)
                    }
                    onEditingFinished: page.commitUrlField()
                }

                Kirigami.Separator { Kirigami.FormData.isSection: true; Layout.fillWidth: true }

                // ── API Token ──
                QQC2.Label {
                    Kirigami.FormData.label: i18n("API Token:")
                    Layout.fillWidth: true
                    text: page.hasStoredToken ? i18n("Token stored.") : i18n("No token stored.")
                    color: page.hasStoredToken ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                }

                QQC2.TextField {
                    id: tokenField
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    placeholderText: i18n("Enter API token…")
                    echoMode: TextInput.Password
                    enabled: !page.busy
                }

                RowLayout {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Button {
                        text: page.busy ? i18n("Saving…") : i18n("Save token")
                        icon.name: "document-save"
                        enabled: !page.busy && tokenField.text.length > 0 && page.profiles.length > 0
                        onClicked: {
                            page.busy = true
                            page.showStatus("", false)
                            page.persistShared()
                            var pid = page.profiles[page.selectedIndex].id
                            Platform.saveToken(null, pid, tokenField.text).then(function() {
                                page.busy = false
                                tokenField.text = ""
                                page.hasStoredToken = true
                                page.showStatus(i18n("Token saved."), false)
                                // Live-apply: root only reads the token from the keychain
                                // once at startup otherwise.
                                root.loadSharedAndConnect()
                            }).catch(function(err) {
                                page.busy = false
                                page.showStatus(err || i18n("Failed to save"), true)
                            })
                        }
                    }

                    QQC2.Button {
                        text: i18n("Clear")
                        icon.name: "edit-delete"
                        enabled: !page.busy && page.hasStoredToken
                        onClicked: {
                            page.busy = true
                            Platform.clearToken(null, page.profiles[page.selectedIndex].id).then(function() {
                                page.busy = false
                                page.hasStoredToken = false
                                page.showStatus(i18n("Token removed."), false)
                                root.loadSharedAndConnect()
                            }).catch(function(err) {
                                page.busy = false
                                page.showStatus(i18n("Failed"), true)
                            })
                        }
                    }

                    QQC2.Button {
                        text: i18n("Test")
                        icon.name: "network-connect"
                        enabled: !page.busy && page.profiles.length > 0
                        onClicked: {
                            page.busy = true
                            page.showStatus(i18n("Testing…"), false)
                            page.persistShared()
                            var profile = page.profiles[page.selectedIndex]
                            var url = TimeTracker.resolveUrl(profile)
                            TimeTracker.applySession(profile.provider || "kimai", profile)
                            Platform.loadToken(null, profile.id).then(function(token) {
                                page.busy = false
                                if (!token) {
                                    page.showStatus(i18n("No token stored."), true)
                                    return
                                }
                                page.showStatus(i18n("Testing… (%1)", url), false)
                                page.tracker.testConnection(url, token, function(result) {
                                    page.busy = false
                                    if (result.ok) {
                                        page.showStatus(i18n("Connection OK!"), false)
                                    } else {
                                        var err = result.error || {}
                                        var detail = err.detail || err.statusText || i18n("Failed")
                                        var type = err.type || ""
                                        if (type === "config") detail = i18n("Missing URL or token (type: %1)", type)
                                        page.showStatus(detail || i18n("Failed"), true)
                                    }
                                })
                            }).catch(function(err) {
                                page.busy = false
                                page.showStatus(err, true)
                            })
                        }
                    }
                }
            }

            // ── Status message ──
            Rectangle { Layout.fillWidth: true; visible: page.statusMessage.length > 0; radius: Kirigami.Units.smallSpacing; height: statusLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                color: page.statusIsError ? Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.15) : Qt.rgba(Kirigami.Theme.positiveTextColor.r, Kirigami.Theme.positiveTextColor.g, Kirigami.Theme.positiveTextColor.b, 0.15)
                border.width: 1; border.color: page.statusIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
                QQC2.Label { id: statusLabel; anchors.fill: parent; anchors.margins: Kirigami.Units.smallSpacing
                    text: page.statusMessage; wrapMode: Text.WordWrap
                    color: page.statusIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor }
            }

            // ── Hidden data fields (like desktop) ──
            QQC2.TextField { id: profilesField; visible: false; text: "[{\"id\":\"default\",\"name\":\"Default\",\"url\":\"\",\"provider\":\"kimai\"}]"
                onTextChanged: { if (!page.syncing) page.parseProfiles() } }
            QQC2.TextField { id: activeProfileField; visible: false; text: "default" }

        }
    }

    Component.onCompleted: loadSharedState()
}
