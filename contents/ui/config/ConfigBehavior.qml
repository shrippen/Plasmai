import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "../../code/secret.js" as Secret
import "../../code/sharedConfig.js" as SharedConfig

ConfigPage {
    id: page

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

    property bool syncing: false
    property bool ready: false
    property bool suppressNotify: false
    property string loadedBehaviorState: ""

    function coerceIdleMinutes(value, fallback) {
        return SharedConfig.coerceInt(value, fallback, 1, 240)
    }

    function behaviorPatch() {
        return {
            confirmBeforeStop: confirmBeforeStopCheck.checked,
            confirmStartBeforePreviousEnd: confirmStartOverlapCheck.checked,
            idleStopEnabled: idleStopCheck.checked,
            idleStopMinutes: idleStopSpin.value,
            notifyOnStart: notifyStartCheck.checked,
            notifyOnStop: notifyStopCheck.checked,
            notifyOnIdleStop: notifyIdleStopCheck.checked,
            notifyForgotToStart: notifyForgotCheck.checked
        }
    }

    function behaviorState() {
        return JSON.stringify(behaviorPatch())
    }

    function syncBehaviorToCfg() {
        page.cfg_confirmBeforeStop = confirmBeforeStopCheck.checked
        page.cfg_confirmStartBeforePreviousEnd = confirmStartOverlapCheck.checked
        page.cfg_idleStopEnabled = idleStopCheck.checked
        page.cfg_idleStopMinutes = idleStopSpin.value
        page.cfg_notifyOnStart = notifyStartCheck.checked
        page.cfg_notifyOnStop = notifyStopCheck.checked
        page.cfg_notifyOnIdleStop = notifyIdleStopCheck.checked
        page.cfg_notifyForgotToStart = notifyForgotCheck.checked
    }

    function applyCfgToControls() {
        suppressNotify = true
        confirmBeforeStopCheck.checked = page.boolFrom(
            page.cfg_confirmBeforeStop, plasmoid.configuration.confirmBeforeStop, false)
        confirmStartOverlapCheck.checked = page.boolFrom(
            page.cfg_confirmStartBeforePreviousEnd,
            plasmoid.configuration.confirmStartBeforePreviousEnd, true)
        idleStopCheck.checked = page.boolFrom(
            page.cfg_idleStopEnabled, plasmoid.configuration.idleStopEnabled, false)
        idleStopSpin.value = page.coerceIdleMinutes(
            plasmoid.configuration.idleStopMinutes !== undefined
                ? plasmoid.configuration.idleStopMinutes
                : page.cfg_idleStopMinutes,
            page.cfg_idleStopMinutesDefault || 15)
        notifyStartCheck.checked = page.boolFrom(
            page.cfg_notifyOnStart, plasmoid.configuration.notifyOnStart, true)
        notifyStopCheck.checked = page.boolFrom(
            page.cfg_notifyOnStop, plasmoid.configuration.notifyOnStop, true)
        notifyIdleStopCheck.checked = page.boolFrom(
            page.cfg_notifyOnIdleStop, plasmoid.configuration.notifyOnIdleStop, true)
        notifyForgotCheck.checked = page.boolFrom(
            page.cfg_notifyForgotToStart, plasmoid.configuration.notifyForgotToStart, false)
        syncBehaviorToCfg()
    }

    function boolFrom(cfg, live, fallback) {
        function coerce(value, ifMissing) {
            if (typeof value === "boolean") {
                return value
            }
            if (value === "true" || value === 1 || value === "1") {
                return true
            }
            if (value === "false" || value === 0 || value === "0") {
                return false
            }
            return ifMissing
        }
        var fromLive = coerce(live, undefined)
        if (typeof fromLive === "boolean") {
            return fromLive
        }
        var fromCfg = coerce(cfg, undefined)
        if (typeof fromCfg === "boolean") {
            return fromCfg
        }
        return fallback
    }

    function applySharedToControls(shared) {
        if (!shared) {
            return
        }
        suppressNotify = true
        if (typeof shared.confirmBeforeStop === "boolean") {
            confirmBeforeStopCheck.checked = shared.confirmBeforeStop
        }
        if (typeof shared.confirmStartBeforePreviousEnd === "boolean") {
            confirmStartOverlapCheck.checked = shared.confirmStartBeforePreviousEnd
        }
        if (typeof shared.idleStopEnabled === "boolean") {
            idleStopCheck.checked = shared.idleStopEnabled
        }
        if (shared.idleStopMinutes !== undefined && shared.idleStopMinutes !== null) {
            idleStopSpin.value = page.coerceIdleMinutes(
                shared.idleStopMinutes, idleStopSpin.value)
        }
        if (typeof shared.notifyOnStart === "boolean") {
            notifyStartCheck.checked = shared.notifyOnStart
        }
        if (typeof shared.notifyOnStop === "boolean") {
            notifyStopCheck.checked = shared.notifyOnStop
        }
        if (typeof shared.notifyOnIdleStop === "boolean") {
            notifyIdleStopCheck.checked = shared.notifyOnIdleStop
        }
        if (typeof shared.notifyForgotToStart === "boolean") {
            notifyForgotCheck.checked = shared.notifyForgotToStart
        }
        syncBehaviorToCfg()
    }

    function notifyEdited() {
        if (suppressNotify || syncing || !ready) {
            return
        }
        syncBehaviorToCfg()
        var currentState = behaviorState()
        if (currentState === loadedBehaviorState) {
            if (unsavedChanges) {
                unsavedChanges = false
                configurationChanged()
                persistShared()
            }
            return
        }
        unsavedChanges = true
        configurationChanged()
        persistShared()
    }

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            Secret.handleData(execSource, sourceName, data)
        }
    }

    function persistShared() {
        if (syncing || !ready) {
            return
        }
        Secret.persistSharedPatch(execSource, page.sharedConfigScript, plasmoid.configuration, page.behaviorPatch())
    }

    function persistBehaviorConfig() {
        syncBehaviorToCfg()
        var patch = page.behaviorPatch()
        Secret.persistSharedPatch(execSource, page.sharedConfigScript, plasmoid.configuration, patch)
        loadedBehaviorState = JSON.stringify(patch)
        unsavedChanges = false
    }

    property var saveConfig: persistBehaviorConfig

    Component.onDestruction: Secret.cancelAll(execSource)

    property bool reloadScheduled: false

    function scheduleBehaviorReload() {
        if (reloadScheduled) {
            return
        }
        reloadScheduled = true
        Qt.callLater(function() {
            reloadScheduled = false
            if (!page.visible) {
                return
            }
            ready = false
            Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
                syncing = true
                suppressNotify = true
                applyCfgToControls()
                if (shared) {
                    SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
                    applySharedToControls(shared)
                }
                loadedBehaviorState = behaviorState()
                unsavedChanges = false
                Qt.callLater(function() {
                    suppressNotify = false
                    syncing = false
                    loadedBehaviorState = behaviorState()
                    unsavedChanges = false
                    ready = true
                })
            })
        })
    }

    onVisibleChanged: if (visible) scheduleBehaviorReload()
    onPageEntered: scheduleBehaviorReload()

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
                text: i18n("Behavior")
            }

            Kirigami.FormLayout {
                id: behaviorForm
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                Layout.bottomMargin: page.pageMargin
                wideMode: page.formWide

                QQC2.CheckBox {
                    id: confirmBeforeStopCheck
                    Kirigami.FormData.label: i18n("Tracking:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Confirm before stopping the timer")
                    onCheckedChanged: page.notifyEdited()
                }

                QQC2.CheckBox {
                    id: confirmStartOverlapCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Ask before a start that overlaps the previous entry")
                    onCheckedChanged: page.notifyEdited()
                }

                QQC2.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: i18n("When editing the running timer, the previous entry’s end is shown. Saving an earlier start asks for confirmation.")
                }

                QQC2.CheckBox {
                    id: idleStopCheck
                    Kirigami.FormData.label: i18n("Idle detection:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Stop timer when idle")
                    onCheckedChanged: page.notifyEdited()
                }

                QQC2.SpinBox {
                    id: idleStopSpin
                    Kirigami.FormData.label: i18n("Idle threshold (minutes):")
                    from: 1
                    to: 240
                    stepSize: 1
                    enabled: idleStopCheck.checked
                    onValueChanged: page.notifyEdited()
                }

                QQC2.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: i18n("Idle detection uses the session idle hint on Wayland (loginctl / ScreenSaver) and xprintidle on X11.")
                }

                QQC2.CheckBox {
                    id: notifyStartCheck
                    Kirigami.FormData.label: i18n("Notifications:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Notify when tracking starts")
                    onCheckedChanged: page.notifyEdited()
                }

                QQC2.CheckBox {
                    id: notifyStopCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Notify when tracking stops")
                    onCheckedChanged: page.notifyEdited()
                }

                QQC2.CheckBox {
                    id: notifyIdleStopCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Notify when stopped due to idle")
                    enabled: idleStopCheck.checked
                    onCheckedChanged: page.notifyEdited()
                }

                QQC2.CheckBox {
                    id: notifyForgotCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Remind me once if nothing is tracking during work hours")
                    onCheckedChanged: page.notifyEdited()
                }
            }
        }
    }
}
