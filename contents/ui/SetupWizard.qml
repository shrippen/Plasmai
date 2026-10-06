import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../code/setupWizard.js" as Wizard
import "../code/platform.js" as Platform
import "../code/timeTracker.js" as TimeTracker
import "../code/profiles.js" as Profiles
import "../code/geocode.js" as Geocode
import "."
import "Kante"
import "Controls" as Controls

/**
 * First-start wizard, shared by the Plasmoid (popup) and the app (timer page)
 * on every platform. Shown while nothing is connected; the host keeps it up
 * until finished() so the Day step still shows after connected().
 *
 *   [System] → Service → Access → Day        (setupWizard.js)
 *
 * The host passes the current settings and applies what comes back:
 *   connected(patch)  profilesJson, activeProfileId, kimaiUrl: the profile is
 *                     usable now (token tested and stored)
 *   finished(patch)   workDayBegin/End, latitude, longitude, locationName,
 *                     notifyForgotToStart: only what was set ({} = skipped)
 */
ColumnLayout {
    id: root

    width: parent ? parent.width : implicitWidth
    spacing: Kirigami.Units.largeSpacing

    /** Plasmoid: its P5Support DataSource for the scripts; app: null. */
    property var dataSource: null
    property var profiles: Profiles.defaultProfiles()
    property string activeProfileId: "default"
    /** The platform can show a reminder (app: a Notifier exists; Plasmoid: always). */
    property bool supportsReminders: true
    property string workDayBegin: "08:00"
    property string workDayEnd: "18:00"
    property string locationName: ""
    property bool notifyForgotToStart: false

    signal connected(var patch)
    signal finished(var patch)

    // —— State ——
    property var issues: []
    property bool checking: false
    property bool keepSystemStep: false
    readonly property var stepList: Wizard.steps(issues, keepSystemStep ? Wizard.SystemStep.KEEP : Wizard.SystemStep.AUTO)
    property int stepIndex: 0
    readonly property string step: stepList[Math.min(stepIndex, stepList.length - 1)]

    property string providerId: "kimai"
    readonly property var providerMeta: TimeTracker.providerMeta(providerId)
    /** Clockify, Toggl: the cloud address unless the user asks for another one. */
    property bool customUrl: false
    readonly property bool showUrlField: providerMeta.needsUrl || customUrl
    readonly property var urlCheck: Wizard.checkUrl(providerId, showUrlField ? urlField.text : providerMeta.defaultUrl)

    property bool busy: false
    property string errorText: ""
    property string errorHint: ""
    property string accountLabel: ""

    property var places: []
    property int placeIndex: -1
    property string placeStatus: ""

    readonly property var notifyIssue: Wizard.issueById(issues, Wizard.Issue.NOTIFY_SEND)
    readonly property var blockingIssue: Wizard.findIssue(issues, Wizard.Severity.BLOCKING)

    /** Start over: the system check first, the fields from the active profile. */
    function start() {
        var active = Profiles.profileById(root.profiles, root.activeProfileId)
        root.providerId = TimeTracker.normalizeProviderId(active ? active.provider : "kimai")
        root.customUrl = false
        urlField.text = active && active.url ? active.url : ""
        tokenField.text = ""
        root.errorText = ""
        root.errorHint = ""
        root.accountLabel = ""
        root.stepIndex = 0
        root.keepSystemStep = false
        setClock(beginField, root.workDayBegin)
        setClock(endField, root.workDayEnd)
        reminderSwitch.checked = root.notifyForgotToStart
        root.places = []
        root.placeIndex = -1
        root.placeStatus = ""
        checkSystem()
    }

    /** "08:30" into a TimeField; an unreadable value shows 00:00. */
    function setClock(field, text) {
        var minutes = Math.max(0, Wizard.clockMinutes(text))
        field.setTime(Math.floor(minutes / 60), minutes % 60)
    }

    function checkSystem() {
        root.checking = true
        Platform.checkSystem(root.dataSource).then(function(result) {
            root.issues = Wizard.assess(result)
            // Once shown, System stays in the list: fixing it must not shift the steps.
            if (Wizard.hasBlocking(root.issues)) {
                root.keepSystemStep = true
            }
            root.checking = false
        })
    }

    function goTo(stepName) {
        var i = root.stepList.indexOf(stepName)
        if (i >= 0) {
            root.errorText = ""
            root.errorHint = ""
            root.stepIndex = i
        }
    }

    function back() {
        if (root.stepIndex > 0) {
            root.errorText = ""
            root.errorHint = ""
            root.stepIndex--
        }
    }

    function stepLabel(stepName) {
        switch (stepName) {
        case Wizard.Step.SYSTEM:
            return i18n("System")
        case Wizard.Step.SERVICE:
            return i18n("Service")
        case Wizard.Step.ACCESS:
            return i18n("Access")
        default:
            return i18n("Day")
        }
    }

    function stepTitle(stepName) {
        switch (stepName) {
        case Wizard.Step.SYSTEM:
            return i18n("Check your system")
        case Wizard.Step.SERVICE:
            return i18n("Choose your time tracker")
        case Wizard.Step.ACCESS:
            return i18n("Connect to %1", TimeTracker.providerDisplayName(root.providerId))
        default:
            return i18n("Your work day")
        }
    }

    /** Where the user finds the token in the service's web interface. */
    function tokenHelp(id) {
        switch (id) {
        case "clockify":
            return i18n("In Clockify: Profile settings, Preferences, tab Advanced, Manage API keys.")
        case "toggl":
            return i18n("In Toggl Track: Profile settings, at the bottom: API Token.")
        case "solidtime":
            return i18n("In SolidTime: open API Tokens from your profile menu and create a token.")
        default:
            return i18n("In Kimai: open API access from your user menu and create a token.")
        }
    }

    function urlProblemText(problem) {
        if (problem === Wizard.UrlProblem.MISSING) {
            return i18n("Enter the server address.")
        }
        if (problem === Wizard.UrlProblem.INVALID) {
            return i18n("This is not a web address (https://…).")
        }
        return ""
    }

    // —— Access: test first, store the token only when it works ——
    function connect() {
        var check = root.urlCheck
        if (check.problem !== Wizard.UrlProblem.NONE) {
            root.errorText = urlProblemText(check.problem)
            return
        }
        var token = Wizard.cleanToken(tokenField.text)
        if (!token) {
            root.errorText = i18n("Paste your API token.")
            return
        }
        if (root.showUrlField) {
            urlField.text = check.url
        }

        var applied = Wizard.applyService(root.profiles, root.activeProfileId, root.providerId,
                                          TimeTracker.providerDisplayName(root.providerId), check.url)
        var index = 0
        for (var i = 0; i < applied.profiles.length; i++) {
            if (applied.profiles[i].id === applied.profileId) {
                index = i
            }
        }
        var tracker = TimeTracker.applySession(root.providerId, applied.profiles[index])

        root.busy = true
        root.errorText = ""
        root.errorHint = ""
        tracker.testConnection(check.url, token, function(result) {
            if (!result.ok) {
                root.busy = false
                root.errorText = ApiErrors.text(result.error, true)
                return
            }
            applied.profiles[index] = Wizard.withConnectionMeta(applied.profiles[index], result.data)
            storeToken(tracker, applied, index, check.url, token)
        })
    }

    function storeToken(tracker, applied, index, url, token) {
        Platform.saveToken(root.dataSource, applied.profileId, token).then(function() {
            tracker.fetchCurrentUser(url, token, function(user) {
                root.busy = false
                root.accountLabel = user && user.ok ? Wizard.userLabel(user.data) : ""
                root.connected({
                    profilesJson: Profiles.serializeProfiles(applied.profiles),
                    activeProfileId: applied.profileId,
                    kimaiUrl: url
                })
                root.goTo(Wizard.Step.DAY)
            })
        }).catch(function(err) {
            root.busy = false
            root.errorText = i18n("The token could not be stored securely: %1", String(err || ""))
            if (Qt.platform.os === "linux") {
                root.errorHint = i18n("Is KWallet or another password storage running?")
            }
        })
    }

    // —— Day ——
    function searchPlace() {
        root.places = []
        root.placeIndex = -1
        root.placeStatus = i18n("Searching…")
        Geocode.search(placeField.text, function(result) {
            if (!result.ok) {
                root.placeStatus = result.error === "empty" ? "" : i18n("Search failed. Check your connection.")
                return
            }
            root.places = result.results.slice(0, 5)
            root.placeIndex = root.places.length > 0 ? 0 : -1
            root.placeStatus = root.places.length > 0 ? "" : i18n("No place found.")
        })
    }

    function pad2(n) {
        return (n < 10 ? "0" : "") + n
    }

    /** A TimeField as "08:30". */
    function clockOf(field) {
        return pad2(field.hours) + ":" + pad2(field.minutes)
    }

    function finish() {
        root.finished(Wizard.dayPatch({
            begin: clockOf(beginField),
            end: clockOf(endField),
            place: root.placeIndex >= 0 ? root.places[root.placeIndex] : null,
            remind: root.supportsReminders ? reminderSwitch.checked : undefined
        }))
    }

    readonly property bool hoursValid: Wizard.validHours(clockOf(beginField), clockOf(endField))

    Component.onCompleted: start()

    // Copy for the install command (QML has no clipboard API of its own).
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    function copyText(text) {
        clipboardHelper.text = text
        clipboardHelper.selectAll()
        clipboardHelper.copy()
    }

    // —— Header: steps ——
    Item {
        Layout.fillWidth: true
        implicitHeight: kanteSteps.implicitHeight * kanteSteps.scale
        visible: KanteStyle.active

        // Kante's steps at their own size, scaled down where the popup is narrower.
        KanteSteps {
            id: kanteSteps
            transformOrigin: Item.TopLeft
            scale: Math.min(1, parent.width / Math.max(1, implicitWidth))
            model: root.stepList.map(function(s) { return root.stepLabel(s) })
            current: root.stepIndex
        }
    }

    Controls.Label {
        Layout.fillWidth: true
        visible: !KanteStyle.active
        opacity: 0.7
        text: i18n("Step %1 of %2", root.stepIndex + 1, root.stepList.length)
    }

    Controls.Label {
        Layout.fillWidth: true
        visible: root.stepIndex === 0
        wrapMode: Text.WordWrap
        text: i18n("Welcome to Plasmai.")
    }

    Controls.Heading {
        Layout.fillWidth: true
        level: 2
        wrapMode: Text.WordWrap
        text: root.stepTitle(root.step)
    }

    // —— System ——
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.step === Wizard.Step.SYSTEM
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Plasmai keeps your API token in the system's password storage (KWallet). That needs a few things on your system.")
        }

        Repeater {
            model: [
                { title: "secret-tool", issue: Wizard.Issue.SECRET_TOOL,
                  missing: i18n("Missing: needed to store the token.") },
                { title: i18n("Password storage (KWallet)"), issue: Wizard.Issue.SECRET_SERVICE,
                  missing: i18n("Not running: turn on KDE Wallet in System Settings.") },
                { title: "notify-send", issue: Wizard.Issue.NOTIFY_SEND,
                  missing: i18n("Missing: reminders stay silent (optional).") }
            ]
            delegate: RowLayout {
                required property var modelData
                readonly property var found: Wizard.issueById(root.issues, modelData.issue)
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    // Form and word, not color alone: ✓ / ✗ / !. One column width for all three.
                    Layout.preferredWidth: Kirigami.Units.gridUnit
                    Layout.alignment: Qt.AlignTop
                    horizontalAlignment: Text.AlignHCenter
                    text: !found ? "✓" : (found.severity === Wizard.Severity.BLOCKING ? "✗" : "!")
                    color: !found ? KanteStyle.positiveTextColor
                         : (found.severity === Wizard.Severity.BLOCKING ? KanteStyle.negativeTextColor : KanteStyle.warningColor)
                    font.bold: true
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Controls.Label {
                        Layout.fillWidth: true
                        text: modelData.title
                        font.bold: true
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.75
                        font.pointSize: KanteStyle.smallFont.pointSize
                        text: found ? modelData.missing : i18n("Ready.")
                    }
                }
            }
        }

        Controls.Label {
            Layout.fillWidth: true
            visible: !!root.blockingIssue
            wrapMode: Text.WordWrap
            text: root.blockingIssue && root.blockingIssue.command
                ? i18n("Install it in a terminal, then check again:")
                : (root.blockingIssue && root.blockingIssue.id === Wizard.Issue.SECRET_TOOL
                   ? i18n("Install the package that provides secret-tool with your package manager, then check again.")
                   : i18n("Then check again."))
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !!root.blockingIssue && root.blockingIssue.command.length > 0

            KanteTextField {
                Layout.fillWidth: true
                readOnly: true
                font.family: KanteStyle.monoFamily
                text: root.blockingIssue ? root.blockingIssue.command : ""
            }
            Controls.Button {
                text: i18n("Copy")
                onClicked: root.copyText(root.blockingIssue.command)
            }
        }
    }

    // —— Service ——
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.step === Wizard.Step.SERVICE
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Which service do you track your time with? More profiles can be added later in the settings.")
        }

        QQC2.ButtonGroup {
            id: serviceGroup
        }

        Repeater {
            model: TimeTracker.listProviders()
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 0

                QQC2.RadioButton {
                    KanteCheckSkin { control: parent; shape: KanteCheckSkin.Shape.Radio }
                    Layout.fillWidth: true
                    QQC2.ButtonGroup.group: serviceGroup
                    text: modelData.name
                    checked: root.providerId === modelData.id
                    onToggled: {
                        if (checked) {
                            root.providerId = modelData.id
                            root.customUrl = false
                        }
                    }
                }
                Controls.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit * 2
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                    font.pointSize: KanteStyle.smallFont.pointSize
                    color: modelData.tested ? KanteStyle.textColor : KanteStyle.warningColor
                    text: modelData.tested
                        ? i18n("Tested with real accounts.")
                        : i18n("Experimental: not yet tested with real accounts.")
                }
            }
        }
    }

    // —— Access ——
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.step === Wizard.Step.ACCESS
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            Layout.fillWidth: true
            visible: root.showUrlField
            text: i18n("Server address")
        }
        KanteTextField {
            id: urlField
            objectName: "setupUrlField"
            Layout.fillWidth: true
            visible: root.showUrlField
            enabled: !root.busy
            placeholderText: root.providerMeta.urlPlaceholder || ""
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            Accessible.name: i18n("Server address")
            onEditingFinished: {
                if (root.urlCheck.problem === Wizard.UrlProblem.NONE && text.length > 0) {
                    text = root.urlCheck.url
                }
            }
        }
        Controls.Label {
            Layout.fillWidth: true
            visible: root.showUrlField && Wizard.hasNote(root.urlCheck, Wizard.UrlNote.TRIMMED)
            wrapMode: Text.WordWrap
            font.pointSize: KanteStyle.smallFont.pointSize
            opacity: 0.75
            text: i18n("Shortened to the address of the Kimai instance: %1", root.urlCheck.url)
        }
        Controls.Label {
            Layout.fillWidth: true
            visible: root.showUrlField && Wizard.hasNote(root.urlCheck, Wizard.UrlNote.INSECURE)
            wrapMode: Text.WordWrap
            font.pointSize: KanteStyle.smallFont.pointSize
            color: KanteStyle.warningColor
            text: i18n("This address is not encrypted (http). Your token would travel readable through the network.")
        }
        Controls.Button {
            visible: !root.providerMeta.needsUrl && !root.customUrl
            flat: true
            text: i18n("Use another address")
            onClicked: {
                root.customUrl = true
                urlField.text = root.providerMeta.defaultUrl
            }
        }

        Controls.Label {
            Layout.fillWidth: true
            text: root.providerMeta.authLabelKey === "key" ? i18n("API key") : i18n("API token")
        }
        RowLayout {
            Layout.fillWidth: true

            KanteTextField {
                id: tokenField
                objectName: "setupTokenField"
                Layout.fillWidth: true
                enabled: !root.busy
                echoMode: showToken.checked ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                Accessible.name: root.providerMeta.authLabelKey === "key" ? i18n("API key") : i18n("API token")
                onAccepted: root.connect()
            }
            Controls.Button {
                id: showToken
                checkable: true
                text: checked ? i18n("Hide") : i18n("Show")
            }
        }
        Controls.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pointSize: KanteStyle.smallFont.pointSize
            opacity: 0.75
            text: root.tokenHelp(root.providerId) + " "
                  + i18n("The token is kept in the system's password storage, never in a plain file.")
        }
    }

    // —— Day ——
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.step === Wizard.Step.DAY
        spacing: Kirigami.Units.smallSpacing

        Kirigami.InlineMessage {
            KanteMessageSkin { message: parent }
            Layout.fillWidth: true
            visible: true
            type: Kirigami.MessageType.Positive
            text: root.accountLabel.length > 0
                ? i18n("Connected as %1.", root.accountLabel)
                : i18n("Connected to %1.", TimeTracker.providerDisplayName(root.providerId))
        }

        Controls.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("So the day bar and the remaining hours fit you. All of this can be changed later in the settings.")
        }

        Controls.Label {
            Layout.fillWidth: true
            text: i18n("Work hours")
            font.bold: true
        }
        RowLayout {
            Layout.fillWidth: true

            TimeField {
                id: beginField
                objectName: "setupBeginField"
                Layout.fillWidth: true
                Accessible.name: i18n("Work day begins")
            }
            Controls.Label {
                text: "–"
            }
            TimeField {
                id: endField
                objectName: "setupEndField"
                Layout.fillWidth: true
                Accessible.name: i18n("Work day ends")
            }
        }
        Controls.Label {
            Layout.fillWidth: true
            visible: !root.hoursValid
            wrapMode: Text.WordWrap
            color: KanteStyle.negativeTextColor
            text: i18n("The work day must end after it begins.")
        }

        Controls.Label {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: i18n("Place for sunrise and sunset")
            font.bold: true
        }
        RowLayout {
            Layout.fillWidth: true

            KanteTextField {
                id: placeField
                Layout.fillWidth: true
                placeholderText: root.locationName.length > 0
                    ? Wizard.shortPlace(root.locationName) : i18n("City")
                Accessible.name: i18n("Place")
                onAccepted: root.searchPlace()
            }
            Controls.Button {
                text: i18n("Search")
                enabled: placeField.text.trim().length > 0
                onClicked: root.searchPlace()
            }
        }
        Controls.Label {
            Layout.fillWidth: true
            visible: text.length > 0
            wrapMode: Text.WordWrap
            opacity: 0.75
            font.pointSize: KanteStyle.smallFont.pointSize
            text: root.placeStatus.length > 0 ? root.placeStatus
                : (root.places.length === 0 && root.locationName.length > 0
                   ? i18n("Current: %1", root.locationName) : "")
        }

        QQC2.ButtonGroup {
            id: placeGroup
        }
        Repeater {
            model: root.places
            delegate: QQC2.RadioButton {
                required property var modelData
                required property int index
                KanteCheckSkin { control: parent; shape: KanteCheckSkin.Shape.Radio }
                Layout.fillWidth: true
                QQC2.ButtonGroup.group: placeGroup
                text: modelData.displayName
                checked: root.placeIndex === index
                onToggled: {
                    if (checked) {
                        root.placeIndex = index
                    }
                }
            }
        }

        QQC2.Switch {
            id: reminderSwitch
            KanteCheckSkin { control: parent; shape: KanteCheckSkin.Shape.Switch }
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            visible: root.supportsReminders
            text: i18n("Remind me on work days when no timer runs")
        }
        Controls.Label {
            Layout.fillWidth: true
            visible: root.supportsReminders && reminderSwitch.checked && !!root.notifyIssue
            wrapMode: Text.WordWrap
            color: KanteStyle.warningColor
            font.pointSize: KanteStyle.smallFont.pointSize
            text: root.notifyIssue && root.notifyIssue.command
                ? i18n("Reminders need notify-send: %1", root.notifyIssue.command)
                : i18n("Reminders need notify-send (libnotify).")
        }
    }

    // —— Messages ——
    Kirigami.InlineMessage {
        KanteMessageSkin { message: parent }
        Layout.fillWidth: true
        visible: root.errorText.length > 0
        type: Kirigami.MessageType.Error
        text: root.errorHint.length > 0 ? root.errorText + "\n" + root.errorHint : root.errorText
    }

    // —— Buttons ——
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Controls.Button {
            visible: root.stepIndex > 0 && root.step !== Wizard.Step.DAY
            enabled: !root.busy
            flat: true
            text: i18n("Back")
            onClicked: root.back()
        }
        Controls.Button {
            visible: root.step === Wizard.Step.DAY
            flat: true
            text: i18n("Skip")
            onClicked: root.finished({})
        }
        Item {
            Layout.fillWidth: true
        }
        Controls.Button {
            visible: root.step === Wizard.Step.SYSTEM
            enabled: !root.checking
            emphasis: root.blockingIssue ? Controls.Button.Emphasis.Primary : Controls.Button.Emphasis.Normal
            busy: root.checking
            text: i18n("Check again")
            onClicked: root.checkSystem()
        }
        Controls.Button {
            visible: root.step === Wizard.Step.SYSTEM || root.step === Wizard.Step.SERVICE
            enabled: !root.checking && !root.blockingIssue
            emphasis: root.blockingIssue ? Controls.Button.Emphasis.Normal : Controls.Button.Emphasis.Primary
            text: i18n("Next")
            onClicked: root.stepIndex++
        }
        Controls.Button {
            visible: root.step === Wizard.Step.ACCESS
            enabled: !root.busy
            emphasis: Controls.Button.Emphasis.Primary
            busy: root.busy
            text: root.busy ? i18n("Connecting…") : i18n("Connect")
            onClicked: root.connect()
        }
        Controls.Button {
            visible: root.step === Wizard.Step.DAY
            enabled: root.hoursValid
            emphasis: Controls.Button.Emphasis.Primary
            text: i18n("Done")
            onClicked: root.finish()
        }
    }
}
