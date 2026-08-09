import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import "../../code/secret.js" as Secret
import "../../code/sharedConfig.js" as SharedConfig

Item {
    id: page

    readonly property string sharedConfigScript: {
        var url = Qt.resolvedUrl("../../code/sharedConfig.sh").toString()
        if (url.indexOf("file://") === 0) {
            return url.substring(7)
        }
        return url
    }

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
        Secret.loadSharedConfig(execSource, page.sharedConfigScript, function(existing) {
            var shared = SharedConfig.merge(
                existing || SharedConfig.fromConfiguration(plasmoid.configuration),
                {
                    confirmBeforeStop: confirmBeforeStopCheck.checked,
                    idleStopEnabled: idleStopCheck.checked,
                    idleStopMinutes: idleStopSpin.value,
                    notifyOnStart: notifyStartCheck.checked,
                    notifyOnStop: notifyStopCheck.checked,
                    notifyOnIdleStop: notifyIdleStopCheck.checked
                }
            )
            Secret.saveSharedConfig(execSource, page.sharedConfigScript, shared)
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

    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Kirigami.Units.largeSpacing
        }
        spacing: Kirigami.Units.largeSpacing

        Kirigami.FormLayout {
            Layout.fillWidth: true

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

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.bold: true
            text: i18n("Global shortcuts")
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.8
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: i18n("Configure shortcuts in System Settings → Keyboard → Shortcuts → Plasma. Look for “Toggle Plasmai tracking” and “Stop Plasmai tracking”.")
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.75
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: i18n("Idle detection requires xprintidle (X11/XWayland). It may not work on pure Wayland sessions.")
        }
    }
}
