import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import "../../code/secret.js" as Secret
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/profiles.js" as Profiles
import "../../code/sharedConfig.js" as SharedConfig
import ".."

Item {
    id: page

    readonly property string kwalletScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/kwallet.sh"))
    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/sharedConfig.sh"))
    readonly property int pageMargin: Kirigami.Units.gridUnit

    property alias cfg_kimaiUrl: kimaiUrlField.text
    property alias cfg_profilesJson: profilesField.text
    property alias cfg_activeProfileId: activeProfileField.text

    property var profiles: Profiles.parseProfiles(profilesField.text, kimaiUrlField.text)
    property int selectedIndex: 0
    property bool updatingFields: false
    property bool syncing: false

    property string statusMessage: ""
    property bool statusIsError: false
    property bool busy: false
    property bool testingConnection: false

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
        Secret.persistSharedPatch(execSource, page.sharedConfigScript, plasmoid.configuration, {
            kimaiUrl: KimaiApi.normalizeUrl(kimaiUrlField.text),
            profilesJson: profilesField.text,
            activeProfileId: activeProfileField.text || "default"
        })
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
        updatingFields = false
    }

    function updateSelectedProfile(field, value) {
        if (updatingFields || syncing || profiles.length === 0 || selectedIndex < 0) {
            return
        }
        var copy = profiles.slice()
        copy[selectedIndex][field] = value
        profiles = copy
        syncProfiles()
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

    Component.onCompleted: {
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            if (shared) {
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
                if (typeof shared.profilesJson === "string" && shared.profilesJson.length > 0) {
                    profilesField.text = shared.profilesJson
                }
                if (typeof shared.activeProfileId === "string" && shared.activeProfileId.length > 0) {
                    activeProfileField.text = shared.activeProfileId
                }
                if (typeof shared.kimaiUrl === "string" && shared.kimaiUrl.length > 0) {
                    kimaiUrlField.text = shared.kimaiUrl
                }
            }
            if (!profilesField.text && kimaiUrlField.text) {
                profiles = Profiles.parseProfiles("", kimaiUrlField.text)
                syncProfiles()
            }
            if (!activeProfileField.text) {
                activeProfileField.text = "default"
            }
            ensureSelection()
        })
    }

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
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                wrapMode: Text.WordWrap
                opacity: 0.8
                text: i18n("Configure your Kimai server connection. Add multiple profiles if you use more than one instance.")
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                wideMode: true

                QQC2.ComboBox {
                    id: profileCombo
                    Kirigami.FormData.label: i18n("Profile:")
                    Layout.fillWidth: true
                    model: page.profiles.map(function(p) { return p.name })
                    currentIndex: page.selectedIndex
                    onActivated: function(index) {
                        page.selectedIndex = index
                        page.updateFieldsForSelection()
                    }
                }

                QQC2.TextField {
                    id: profileNameField
                    Kirigami.FormData.label: i18n("Profile name:")
                    Layout.fillWidth: true
                    onTextChanged: page.updateSelectedProfile("name", text)
                }

                QQC2.TextField {
                    id: kimaiUrlField
                    Kirigami.FormData.label: i18n("Kimai server URL:")
                    Layout.fillWidth: true
                    placeholderText: i18n("https://kimai.example.com")
                    onTextChanged: {
                        if (!page.updatingFields && !page.syncing) {
                            // Keep raw text while typing; normalize only when leaving the field.
                            page.updateSelectedProfile("url", text)
                        }
                    }
                    onEditingFinished: page.commitUrlField()
                }

                QQC2.TextField {
                    id: tokenField
                    Kirigami.FormData.label: i18n("API token:")
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: i18n("Paste token to save in KWallet")
                    enabled: !page.busy
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Button {
                    text: i18n("Add profile")
                    icon.name: "list-add"
                    onClicked: {
                        var copy = page.profiles.slice()
                        var profile = Profiles.normalizeProfile({
                            id: Profiles.newProfileId(),
                            name: i18n("Profile %1", copy.length + 1),
                            url: ""
                        })
                        copy.push(profile)
                        page.profiles = copy
                        page.syncProfiles()
                        page.selectedIndex = copy.length - 1
                        profileCombo.currentIndex = page.selectedIndex
                        page.updateFieldsForSelection()
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
                    }
                }

                PlasmaComponents3.Button {
                    text: i18n("Use this profile")
                    icon.name: "emblem-default"
                    enabled: page.profiles.length > 0
                    onClicked: page.setActiveProfile()
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                wrapMode: Text.WordWrap
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.75
                text: {
                    var active = Profiles.profileById(page.profiles, activeProfileField.text || "default")
                    return i18n("Active profile: %1", active ? active.name : i18n("none"))
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
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
                    enabled: !page.busy && page.profiles.length > 0
                    onClicked: {
                        page.busy = true
                        page.showStatus("", false)
                        var profileId = page.profiles[page.selectedIndex].id
                        Secret.clear(execSource, page.kwalletScript, profileId, function(ok, err) {
                            page.busy = false
                            if (ok) {
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
                    enabled: !page.testingConnection && kimaiUrlField.text.length > 0 && !page.busy
                    onClicked: {
                        page.testingConnection = true
                        page.showStatus(i18n("Testing connection…"), false)
                        page.commitUrlField()
                        var profileId = page.profiles[page.selectedIndex].id
                        var url = KimaiApi.normalizeUrl(kimaiUrlField.text)
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
                            KimaiApi.testConnection(url, token, function(result) {
                                page.testingConnection = false
                                if (result.ok) {
                                    page.showStatus(
                                        i18n("Connected! Kimai version: %1", result.data.version || i18n("unknown")),
                                        false)
                                } else {
                                    page.showStatus(ApiErrors.text(result.error, true), true)
                                }
                            })
                        })
                    }
                }

                QQC2.BusyIndicator {
                    running: page.testingConnection
                    visible: page.testingConnection
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                visible: page.statusMessage !== ""
                text: page.statusMessage
                wrapMode: Text.WordWrap
                color: page.statusIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                Layout.bottomMargin: page.pageMargin
                wrapMode: Text.WordWrap
                opacity: 0.75
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: i18n("Generate an API token in Kimai under your user profile → API Access. Tokens are stored securely in KWallet per profile.")
            }

            QQC2.TextField {
                id: profilesField
                visible: false
            }

            QQC2.TextField {
                id: activeProfileField
                visible: false
            }
        }
    }
}
