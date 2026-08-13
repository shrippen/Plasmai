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
        Secret.persistSharedPatch(execSource, page.sharedConfigScript, plasmoid.configuration, {
            confirmBeforeStop: confirmBeforeStopCheck.checked,
            idleStopEnabled: idleStopCheck.checked,
            idleStopMinutes: idleStopSpin.value,
            notifyOnStart: notifyStartCheck.checked,
            notifyOnStop: notifyStopCheck.checked,
            notifyOnIdleStop: notifyIdleStopCheck.checked
        })
    }

    Component.onDestruction: Secret.cancelAll(execSource)

    onPageEntered: {
        confirmBeforeStopCheck.checked = !!page.cfg_confirmBeforeStop
        idleStopCheck.checked = !!page.cfg_idleStopEnabled
        if (typeof page.cfg_idleStopMinutes === "number") {
            idleStopSpin.value = page.cfg_idleStopMinutes
        }
        notifyStartCheck.checked = page.cfg_notifyOnStart !== false
        notifyStopCheck.checked = page.cfg_notifyOnStop !== false
        notifyIdleStopCheck.checked = page.cfg_notifyOnIdleStop !== false
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(shared) {
            if (shared) {
                syncing = true
                SharedConfig.applyToConfiguration(plasmoid.configuration, shared)
                if (typeof shared.confirmBeforeStop === "boolean") {
                    confirmBeforeStopCheck.checked = shared.confirmBeforeStop
                }
                if (typeof shared.idleStopEnabled === "boolean") {
                    idleStopCheck.checked = shared.idleStopEnabled
                }
                if (typeof shared.idleStopMinutes === "number") {
                    idleStopSpin.value = shared.idleStopMinutes
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
                syncing = false
            }
            ready = true
        })
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
                    onCheckedChanged: {
                        page.cfg_confirmBeforeStop = checked
                        page.persistShared()
                    }
                }

                QQC2.CheckBox {
                    id: idleStopCheck
                    Kirigami.FormData.label: i18n("Idle detection:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Stop timer when idle")
                    onCheckedChanged: {
                        page.cfg_idleStopEnabled = checked
                        page.persistShared()
                    }
                }

                QQC2.SpinBox {
                    id: idleStopSpin
                    Kirigami.FormData.label: i18n("Idle threshold (minutes):")
                    from: 1
                    to: 240
                    stepSize: 1
                    enabled: idleStopCheck.checked
                    onValueChanged: {
                        page.cfg_idleStopMinutes = value
                        page.persistShared()
                    }
                }

                QQC2.Label {
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: i18n("Idle detection requires xprintidle (X11/XWayland). It may not work on pure Wayland sessions.")
                }

                QQC2.CheckBox {
                    id: notifyStartCheck
                    Kirigami.FormData.label: i18n("Notifications:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Notify when tracking starts")
                    onCheckedChanged: {
                        page.cfg_notifyOnStart = checked
                        page.persistShared()
                    }
                }

                QQC2.CheckBox {
                    id: notifyStopCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Notify when tracking stops")
                    onCheckedChanged: {
                        page.cfg_notifyOnStop = checked
                        page.persistShared()
                    }
                }

                QQC2.CheckBox {
                    id: notifyIdleStopCheck
                    Kirigami.FormData.label: page.formWide ? " " : ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: page.buddyMaxWidth(behaviorForm)
                    text: i18n("Notify when stopped due to idle")
                    enabled: idleStopCheck.checked
                    onCheckedChanged: {
                        page.cfg_notifyOnIdleStop = checked
                        page.persistShared()
                    }
                }
            }
        }
    }
}
