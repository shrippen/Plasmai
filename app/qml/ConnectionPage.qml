import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "shared"
import "../contents/code/profiles.js" as Profiles
import "../contents/code/providerUtil.js" as ProviderUtil
import "Kante"

Kirigami.Page {
    id: page
    readonly property QtObject session: root.session
    KantePageTitle { page: page }
    title: i18n("Connection")

    // The profile list and its actions; the page binds its fields to it.
    ProfileFormModel {
        id: form
        session: page.session
        providers: page.providers
        onEdited: page.syncProfiles()
        onFieldsReset: {
            profileCombo.currentIndex = form.selectedIndex
            profileNameField.text = form.selectedProfile.name
            urlField.text = form.selectedProfile.url || ""
            providerCombo.currentIndex = form.selectedProviderIndex
        }
        onUrlReset: urlField.text = form.selectedProfile.url || ""
        onProviderSwitched: page.showStatus("", false)
    }
    property alias profiles: form.profiles
    property alias selectedIndex: form.selectedIndex
    property alias updatingFields: form.updatingFields
    property alias syncing: form.syncing
    property bool busy: false
    property bool hasStoredToken: false
    property string statusMessage: ""
    property bool statusIsError: false

    readonly property var selectedProfile: form.selectedProfile
    readonly property string selectedProviderId: form.selectedProviderId
    readonly property var selectedProviderMeta: form.selectedProviderMeta
    /** Every service in display order (id, name, needsUrl, defaultUrl, …). */
    readonly property var providers: session.setup.listProviders()

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
        form.ensureSelection(activeProfileField.text, urlField.text)
    }

    function setActiveProfile() {
        activeProfileField.text = form.activate(urlField.text)
        persistShared()
        // Live-apply the newly active profile so the timer view doesn't need
        // an app restart to notice (root only reads shared.json at startup
        // otherwise).
        session.open()
    }

    // ── Persistence ──

    function checkStoredToken() {
        if (profiles.length === 0 || selectedIndex < 0) {
            hasStoredToken = false
            return
        }
        session.connection.hasToken(profiles[selectedIndex].id).then(function(has) {
            // The page is gone: nothing to show.
            if (!page) { return }
            hasStoredToken = has
        })
    }

    function persistShared() {
        var base = { kimaiUrl: urlField.text.trim(), profilesJson: profilesField.text, activeProfileId: activeProfileField.text || "default" }
        session.connection.saveProfiles(base)
    }

    function loadSharedState() {
        session.connection.loadStored().then(function(shared) {
            if (!page) { return }
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
        // The scroll bar sits at the screen edge; the content keeps the page margin.
        anchors.rightMargin: -page.rightPadding
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: formCol
            // Centered, capped width once the page is wider than a form needs — long
            // label/field rows stretched across a landscape screen just look sparse.
            width: Math.min((pageScroll.availableWidth - page.rightPadding), Kirigami.Units.gridUnit * 40)
            x: Math.max(0, ((pageScroll.availableWidth - page.rightPadding) - width) / 2)
            spacing: Kirigami.Units.smallSpacing

            Kirigami.FormLayout {
                Layout.fillWidth: true
                wideMode: formCol.width >= Kirigami.Units.gridUnit * 28

                // ── Profile selector ──
                QQC2.ComboBox {
                    KanteFieldSkin { control: parent }
                    id: profileCombo
                    Kirigami.FormData.label: i18n("Profile:")
                    Layout.fillWidth: true
                    model: page.profiles.map(function(p) { return p.name })
                    currentIndex: page.selectedIndex
                    onActivated: function(index) {
                        if (page.updatingFields) return
                        form.select(index)
                        page.checkStoredToken()
                    }
                }

                KanteTextField {
                    id: profileNameField
                    Kirigami.FormData.label: i18n("Profile name:")
                    Layout.fillWidth: true
                    onEditingFinished: {
                        if (page.updatingFields) return
                        if (!form.rename(text)) {
                            page.showStatus(i18n("A profile named \"%1\" already exists.", text.trim()), true)
                            return
                        }
                        page.showStatus("", false)
                        profileCombo.currentIndex = form.selectedIndex
                    }
                }

                // Flow, not RowLayout: three buttons do not fit a phone in portrait and would widen the whole form.
                Flow {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    // A wrapped Flow reports its narrow wrapped width, and the narrow FormLayout sizes every field to its widest child.
                    Layout.preferredWidth: formCol.width
                    spacing: Kirigami.Units.smallSpacing

                    KanteButton {
                        text: i18n("Add")
                        icon.name: "list-add"
                        onClicked: {
                            form.add(function(n) { return i18n("Profile %1", n) })
                            page.checkStoredToken()
                            page.persistShared()
                        }
                    }

                    KanteButton {
                        text: i18n("Remove")
                        icon.name: "list-remove"
                        enabled: page.profiles.length > 1
                        onClicked: {
                            if (form.removeSelected(activeProfileField.text)) page.setActiveProfile()
                            page.checkStoredToken()
                            page.persistShared()
                        }
                    }

                    KanteButton {
                        text: i18n("Use this")
                        icon.name: "emblem-default"
                        // Switching profiles is online only (offline.js): the outbox belongs to the profile.
                        enabled: page.profiles.length > 0 && !session.sync.offline
                        onClicked: { page.setActiveProfile(); page.checkStoredToken() }
                    }
                }

                QQC2.Label {
                    visible: session.sync.offline
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    Layout.preferredWidth: formCol.width
                    wrapMode: Text.WordWrap
                    text: i18n("Switching profiles needs a connection to the server.")
                }

                QQC2.Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    text: {
                        var active = Profiles.profileById(page.profiles, activeProfileField.text || "default")
                        return i18n("Active: %1", active ? active.name : i18n("none"))
                    }
                    color: KanteStyle.disabledTextColor
                    font.pointSize: KanteStyle.smallFont.pointSize
                }

                Kirigami.Separator { Kirigami.FormData.isSection: true; Layout.fillWidth: true }

                // ── Provider ──
                QQC2.ComboBox {
                    KanteFieldSkin { control: parent }
                    id: providerCombo
                    Kirigami.FormData.label: i18n("Provider:")
                    Layout.fillWidth: true
                    model: page.providers.map(function(p) { return p.name })
                    onActivated: function(index) {
                        if (page.updatingFields) return
                        form.changeProvider(page.providers[index].id)
                    }
                }

                KanteTextField {
                    id: urlField
                    Kirigami.FormData.label: i18n("Server URL:")
                    Layout.fillWidth: true
                    placeholderText: page.selectedProviderMeta.defaultUrl || i18n("https://your-server.com")
                    onTextChanged: {
                        if (!page.updatingFields && !page.syncing) form.updateSelected("url", text)
                    }
                    onEditingFinished: form.commitUrl(urlField.text)
                }

                Kirigami.Separator { Kirigami.FormData.isSection: true; Layout.fillWidth: true }

                // ── API Token ──
                QQC2.Label {
                    Kirigami.FormData.label: i18n("API Token:")
                    Layout.fillWidth: true
                    text: page.hasStoredToken ? i18n("Token stored.") : i18n("No token stored.")
                    color: page.hasStoredToken ? KanteStyle.positiveTextColor : KanteStyle.disabledTextColor
                }

                KanteTextField {
                    id: tokenField
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    placeholderText: i18n("Enter API token…")
                    echoMode: TextInput.Password
                    enabled: !page.busy
                }

                // Flow, not RowLayout: three buttons do not fit a phone in portrait and would widen the whole form.
                Flow {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    // A wrapped Flow reports its narrow wrapped width, and the narrow FormLayout sizes every field to its widest child.
                    Layout.preferredWidth: formCol.width
                    spacing: Kirigami.Units.smallSpacing

                    KanteButton {
                        text: page.busy ? i18n("Saving…") : i18n("Save token")
                        icon.name: "document-save"
                        enabled: !page.busy && tokenField.text.length > 0 && page.profiles.length > 0
                        onClicked: {
                            page.busy = true
                            page.showStatus("", false)
                            page.persistShared()
                            var pid = page.profiles[page.selectedIndex].id
                            // Kept for the answer: the page may be gone by then.
                            const sess = session
                            sess.connection.saveToken(pid, tokenField.text).then(function() {
                                // Live-apply: root only reads the token from the keychain
                                // once at startup otherwise.
                                sess.open()
                                if (!page) { return }
                                page.busy = false
                                tokenField.text = ""
                                page.hasStoredToken = true
                                page.showStatus(i18n("Token saved."), false)
                            }).catch(function(err) {
                                if (!page) { return }
                                page.busy = false
                                page.showStatus(err || i18n("Failed to save"), true)
                            })
                        }
                    }

                    KanteButton {
                        text: i18n("Clear")
                        icon.name: "edit-delete"
                        enabled: !page.busy && page.hasStoredToken
                        onClicked: {
                            page.busy = true
                            // Kept for the answer: the page may be gone by then.
                            const sess = session
                            sess.connection.clearToken(page.profiles[page.selectedIndex].id).then(function() {
                                sess.open()
                                if (!page) { return }
                                page.busy = false
                                page.hasStoredToken = false
                                page.showStatus(i18n("Token removed."), false)
                            }).catch(function(err) {
                                if (!page) { return }
                                page.busy = false
                                page.showStatus(i18n("Failed"), true)
                            })
                        }
                    }

                    KanteButton {
                        text: i18n("Test")
                        icon.name: "network-connect"
                        enabled: !page.busy && page.profiles.length > 0
                        onClicked: {
                            page.busy = true
                            page.showStatus(i18n("Testing…"), false)
                            page.persistShared()
                            const profile = page.profiles[page.selectedIndex]
                            session.connection.testProfile(page.profiles, page.selectedIndex, {
                                noToken: function() {
                                    if (!page) { return }
                                    page.busy = false
                                    page.showStatus(i18n("No token stored."), true)
                                },
                                testing: function(url) {
                                    if (!page) { return }
                                    page.busy = false
                                    page.showStatus(i18n("Testing… (%1)", url), false)
                                },
                                done: function(result) {
                                    if (!page) { return }
                                    page.busy = false
                                    if (result.ok) {
                                        form.applyTested(result.profiles)
                                        page.persistShared()
                                    }
                                    page.showStatus(ApiErrors.testText(result, session.setup.providerName(profile.provider)), !result.ok)
                                },
                                failed: function(err) {
                                    if (!page) { return }
                                    page.busy = false
                                    page.showStatus(err, true)
                                }
                            })
                        }
                    }
                }
            }

            // ── Status message ──
            KanteCallout {
                Layout.fillWidth: true
                visible: KanteStyle.active && page.statusMessage.length > 0
                kind: page.statusIsError ? KanteCallout.Kind.Danger : KanteCallout.Kind.Ok
                text: page.statusMessage
            }
            Rectangle { Layout.fillWidth: true; visible: !KanteStyle.active && page.statusMessage.length > 0; radius: Kirigami.Units.smallSpacing; height: statusLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                color: page.statusIsError ? KanteStyle.tint(KanteStyle.negativeTextColor, 0.15) : KanteStyle.tint(KanteStyle.positiveTextColor, 0.15)
                border.width: 1; border.color: page.statusIsError ? KanteStyle.negativeTextColor : KanteStyle.positiveTextColor
                QQC2.Label { id: statusLabel; anchors.fill: parent; anchors.margins: Kirigami.Units.smallSpacing
                    text: page.statusMessage; wrapMode: Text.WordWrap
                    color: page.statusIsError ? KanteStyle.negativeTextColor : KanteStyle.positiveTextColor }
            }

            // ── Hidden data fields (like desktop) ──
            KanteTextField { id: profilesField; visible: false; text: "[{\"id\":\"default\",\"name\":\"Default\",\"url\":\"\",\"provider\":\"kimai\"}]"
                onTextChanged: { if (!page.syncing) page.parseProfiles() } }
            KanteTextField { id: activeProfileField; visible: false; text: "default" }

        }
    }

    Component.onCompleted: loadSharedState()

}
