import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "../../code/secret.js" as Secret
import "../../code/sharedConfig.js" as SharedConfig

Item {
    id: page

    readonly property string sharedConfigScript: Secret.fileUrlToPath(Qt.resolvedUrl("../../code/sharedConfig.sh"))
    readonly property int pageMargin: Kirigami.Units.gridUnit

    property alias cfg_idleStopEnabled: idleStopCheck.checked
    property alias cfg_idleStopMinutes: idleStopSpin.value
    property alias cfg_notifyOnStart: notifyStartCheck.checked
    property alias cfg_notifyOnStop: notifyStopCheck.checked
    property alias cfg_notifyOnIdleStop: notifyIdleStopCheck.checked
    property alias cfg_confirmBeforeStop: confirmBeforeStopCheck.checked

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

    Component.onCompleted: {
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
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                wideMode: true

                QQC2.CheckBox {
                    id: confirmBeforeStopCheck
                    Kirigami.FormData.label: i18n("Tracking:")
                    text: i18n("Confirm before stopping the timer")
                    onCheckedChanged: page.persistShared()
                }

                QQC2.CheckBox {
                    id: idleStopCheck
                    Kirigami.FormData.label: i18n("Idle detection:")
                    text: i18n("Stop timer when idle")
                    onCheckedChanged: page.persistShared()
                }

                QQC2.SpinBox {
                    id: idleStopSpin
                    Kirigami.FormData.label: i18n("Idle threshold (minutes):")
                    from: 1
                    to: 240
                    stepSize: 1
                    enabled: idleStopCheck.checked
                    onValueChanged: page.persistShared()
                }

                QQC2.CheckBox {
                    id: notifyStartCheck
                    Kirigami.FormData.label: i18n("Notifications:")
                    text: i18n("Notify when tracking starts")
                    onCheckedChanged: page.persistShared()
                }

                QQC2.CheckBox {
                    id: notifyStopCheck
                    Kirigami.FormData.label: " "
                    text: i18n("Notify when tracking stops")
                    onCheckedChanged: page.persistShared()
                }

                QQC2.CheckBox {
                    id: notifyIdleStopCheck
                    Kirigami.FormData.label: " "
                    text: i18n("Notify when stopped due to idle")
                    enabled: idleStopCheck.checked
                    onCheckedChanged: page.persistShared()
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: page.pageMargin
                Layout.rightMargin: page.pageMargin
                Layout.bottomMargin: page.pageMargin
                wrapMode: Text.WordWrap
                opacity: 0.75
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: i18n("Idle detection requires xprintidle (X11/XWayland). It may not work on pure Wayland sessions.")
            }
        }
    }
}
