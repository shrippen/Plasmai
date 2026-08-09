import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
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

    property alias cfg_refreshInterval: refreshIntervalSpin.value
    property alias cfg_recentCount: recentCountSpin.value
    property alias cfg_showElapsedInPanel: showElapsedCheck.checked
    property alias cfg_showProjectInPanel: showProjectCheck.checked

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
                    refreshInterval: refreshIntervalSpin.value,
                    recentCount: recentCountSpin.value,
                    showElapsedInPanel: showElapsedCheck.checked,
                    showProjectInPanel: showProjectCheck.checked
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
                if (typeof shared.refreshInterval === "number") {
                    refreshIntervalSpin.value = shared.refreshInterval
                }
                if (typeof shared.recentCount === "number") {
                    recentCountSpin.value = shared.recentCount
                }
                if (typeof shared.showElapsedInPanel === "boolean") {
                    showElapsedCheck.checked = shared.showElapsedInPanel
                }
                if (typeof shared.showProjectInPanel === "boolean") {
                    showProjectCheck.checked = shared.showProjectInPanel
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

            QQC2.SpinBox {
                id: refreshIntervalSpin
                Kirigami.FormData.label: i18n("Refresh interval (seconds):")
                from: 10
                to: 300
                stepSize: 5
                onValueChanged: page.persistShared()
            }

            QQC2.SpinBox {
                id: recentCountSpin
                Kirigami.FormData.label: i18n("Recent activities shown:")
                from: 3
                to: 25
                stepSize: 1
                onValueChanged: page.persistShared()
            }

            QQC2.CheckBox {
                id: showElapsedCheck
                Kirigami.FormData.label: i18n("Panel:")
                text: i18n("Show elapsed time in panel")
                onCheckedChanged: page.persistShared()
            }

            QQC2.CheckBox {
                id: showProjectCheck
                Kirigami.FormData.label: " "
                text: i18n("Show project name in panel")
                onCheckedChanged: page.persistShared()
            }
        }
    }
}
