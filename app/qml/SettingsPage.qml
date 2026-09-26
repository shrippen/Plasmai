import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/platform.js" as Platform
import "../contents/code/geocode.js" as Geocode
import "shared"
import "Kante"

Kirigami.Page {
    id: page
    KantePageTitle { page: page }
    title: i18n("Settings")

    property string locationQuery: ""
    property var locationResults: []
    property bool locationSearching: false

    function saveSetting(key, value) {
        var patch = {}; patch[key] = value
        Platform.patchShared(null, root.currentConfig(), patch)
    }

    Timer {
        id: locationSearchTimer
        interval: 400; repeat: false
        onTriggered: {
            if (page.locationQuery.trim().length < 2) { page.locationResults = []; return }
            page.locationSearching = true
            Geocode.search(page.locationQuery, function(result) {
                page.locationSearching = false
                page.locationResults = (result.ok && result.results) ? result.results : []
            })
        }
    }

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: form
            // Centered, capped width once the page is wider than a form needs — long
            // label/field rows stretched across a landscape screen just look sparse.
            width: Math.min(pageScroll.availableWidth, Kirigami.Units.gridUnit * 40)
            x: Math.max(0, (pageScroll.availableWidth - width) / 2)
            spacing: Kirigami.Units.smallSpacing

            Kirigami.FormLayout {
                Layout.fillWidth: true
                wideMode: form.width >= Kirigami.Units.gridUnit * 28

                KanteHeading { Kirigami.FormData.isSection: true; level: 4; text: i18n("Appearance") }

                QQC2.ComboBox {
                    KanteFieldSkin { control: parent }
                    Kirigami.FormData.label: i18n("Style:")
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                    model: [i18n("System (Plasma theme)"), i18n("Kante"), i18n("Kante Light")]
                    // Bound after the model is set: assigning the model resets currentIndex.
                    Component.onCompleted: currentIndex = Qt.binding(function() { return root.visualStyle })
                    onActivated: function(index) { root.visualStyle = index; page.saveSetting("visualStyle", index) }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                    wrapMode: Text.WordWrap
                    font.pointSize: KanteStyle.smallFont.pointSize
                    opacity: 0.7
                    text: i18n("Kante is Plasmai's own look: warm colors, square cut corners and monospace figures. It deliberately does not follow Breeze; dark or light still follows your theme. Kante Light keeps your theme's colors and controls and adds only Kante's shapes, titles and figures.")
                }

                KanteHeading { Kirigami.FormData.isSection: true; level: 4; text: i18n("Behavior") }

                QQC2.SpinBox {
                    KanteFieldSkin { control: parent }
                    id: refreshSpin
                    Kirigami.FormData.label: i18n("Refresh interval:")
                    from: 5; to: 300; stepSize: 5
                    value: root.refreshInterval
                    textFromValue: function(value) { return value + "s" }
                    onValueChanged: { root.refreshInterval = value; page.saveSetting("refreshInterval", value) }
                }

                QQC2.SpinBox {
                    KanteFieldSkin { control: parent }
                    Kirigami.FormData.label: i18n("Recent entries:")
                    from: 3; to: 50; value: root.recentCount
                    textFromValue: function(v) { return v }
                    onValueChanged: { root.recentCount = value; page.saveSetting("recentCount", value) }
                }

                WrapCheckBox {
                    Kirigami.FormData.label: i18n("Timer view:")
                    text: i18n("Show work summary (today / week totals)")
                    checked: root.showWorkSummary
                    onToggled: { root.showWorkSummary = checked; page.saveSetting("popupShowWorkSummary", checked) }
                }
                WrapCheckBox {
                    text: i18n("Show recent entries")
                    checked: root.showRecent
                    onToggled: { root.showRecent = checked; page.saveSetting("popupShowRecent", checked) }
                }
                WrapCheckBox {
                    text: i18n("Show favorites")
                    checked: root.showFavorites
                    onToggled: { root.showFavorites = checked; page.saveSetting("popupShowFavorites", checked) }
                }
                WrapCheckBox {
                    text: i18n("Show \"Continue\" button")
                    checked: root.showContinue
                    onToggled: { root.showContinue = checked; page.saveSetting("popupShowContinue", checked) }
                }
                WrapCheckBox {
                    text: i18n("Show start / switch activity controls")
                    checked: root.showNewActivity
                    onToggled: { root.showNewActivity = checked; page.saveSetting("popupShowNewActivity", checked) }
                }
                WrapCheckBox {
                    id: showSparklineCheck
                    text: i18n("Show day sparkline")
                    checked: root.showSparkline
                    onToggled: { root.showSparkline = checked; page.saveSetting("popupShowSparkline", checked) }
                }
                WrapCheckBox {
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    enabled: showSparklineCheck.checked
                    text: i18n("Show sun, moon, and work arcs")
                    checked: root.showSparklineArcs
                    onToggled: { root.showSparklineArcs = checked; page.saveSetting("showSparklineArcs", checked) }
                }

                WrapCheckBox {
                    Kirigami.FormData.label: i18n("Trips:")
                    text: i18n("Log trips and show detected trips (Anfahrten plugin)")
                    checked: root.showTrips
                    onToggled: { root.showTrips = checked; page.saveSetting("showTrips", checked); root.resolveMileage(false) }
                }

                WrapCheckBox {
                    Kirigami.FormData.label: i18n("Confirmations:")
                    text: i18n("Confirm before stopping tracking")
                    checked: root.confirmBeforeStop
                    onToggled: { root.confirmBeforeStop = checked; page.saveSetting("confirmBeforeStop", checked) }
                }
                WrapCheckBox {
                    text: i18n("Ask before a start that overlaps the previous entry")
                    checked: root.confirmStartBeforePreviousEnd
                    onToggled: { root.confirmStartBeforePreviousEnd = checked; page.saveSetting("confirmStartBeforePreviousEnd", checked) }
                }
                QQC2.Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    opacity: 0.75; font.pointSize: KanteStyle.smallFont.pointSize
                    text: i18n("When editing the running timer, the previous entry's end is shown. Saving an earlier start asks for confirmation.")
                }

                KanteHeading { Kirigami.FormData.isSection: true; level: 4; text: i18n("Work hours") }

                KanteTextField {
                    Kirigami.FormData.label: i18n("Begin:")
                    text: root.workDayBegin
                    placeholderText: "09:00"
                    onEditingFinished: { root.workDayBegin = text; page.saveSetting("workDayBegin", text) }
                }
                KanteTextField {
                    Kirigami.FormData.label: i18n("End:")
                    text: root.workDayEnd
                    placeholderText: "17:00"
                    onEditingFinished: { root.workDayEnd = text; page.saveSetting("workDayEnd", text) }
                }

                KanteHeading { Kirigami.FormData.isSection: true; level: 4; text: i18n("Location (sun / moon accuracy)") }

                QQC2.Label {
                    Kirigami.FormData.label: i18n("Current:")
                    text: root.locationName.length > 0 ? root.locationName : i18n("%1, %2", root.latitude.toFixed(2), root.longitude.toFixed(2))
                    color: Qt.alpha(KanteStyle.textColor, 0.7)
                }

                KanteTextField {
                    id: locationField
                    Kirigami.FormData.label: i18n("Search city:")
                    placeholderText: i18n("Search for a city…")
                    // Predictive keyboards deliver text as uncommitted preedit, so the search would only start after commit.
                    inputMethodHints: Qt.ImhNoPredictiveText
                    onTextChanged: { page.locationQuery = text; locationSearchTimer.restart() }
                }

                ColumnLayout {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    spacing: 0
                    visible: page.locationSearching || page.locationResults.length > 0

                    QQC2.BusyIndicator { visible: page.locationSearching; Layout.alignment: Qt.AlignLeft; Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Kirigami.Units.iconSizes.small }

                    Repeater {
                        model: page.locationResults
                        delegate: QQC2.ItemDelegate {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.displayName
                            icon.name: "mark-location"
                            onClicked: {
                                root.latitude = modelData.latitude; root.longitude = modelData.longitude; root.locationName = modelData.displayName
                                page.saveSetting("latitude", modelData.latitude)
                                page.saveSetting("longitude", modelData.longitude)
                                page.saveSetting("locationName", modelData.displayName)
                                page.locationResults = []; locationField.text = ""
                            }
                        }
                    }
                }

                KanteHeading { Kirigami.FormData.isSection: true; level: 4; text: i18n("Idle detection"); visible: root.supportsIdleDetection }
                WrapCheckBox {
                    Kirigami.FormData.label: i18n("Enable:")
                    visible: root.supportsIdleDetection
                    text: i18n("Prompt after being idle while tracking")
                    checked: root.idleStopEnabled
                    onToggled: { root.idleStopEnabled = checked; page.saveSetting("idleStopEnabled", checked) }
                }
                QQC2.SpinBox {
                    KanteFieldSkin { control: parent }
                    Kirigami.FormData.label: i18n("Idle after:")
                    visible: root.supportsIdleDetection
                    from: 3; to: 120; value: root.idleStopMinutes
                    textFromValue: function(v) { return i18n("%1 min", v) }
                    onValueChanged: { root.idleStopMinutes = value; page.saveSetting("idleStopMinutes", value) }
                }

                KanteHeading { Kirigami.FormData.isSection: true; level: 4; text: i18n("Notifications"); visible: root.supportsNotifications }
                WrapCheckBox {
                    Kirigami.FormData.label: i18n("Notify on:")
                    visible: root.supportsNotifications
                    text: i18n("Start")
                    checked: root.notifyOnStart
                    onToggled: { root.notifyOnStart = checked; page.saveSetting("notifyOnStart", checked) }
                }
                WrapCheckBox {
                    visible: root.supportsNotifications
                    text: i18n("Stop")
                    checked: root.notifyOnStop
                    onToggled: { root.notifyOnStop = checked; page.saveSetting("notifyOnStop", checked) }
                }
                WrapCheckBox {
                    visible: root.supportsNotifications && root.supportsIdleDetection
                    text: i18n("Idle stop")
                    checked: root.notifyOnIdleStop
                    onToggled: { root.notifyOnIdleStop = checked; page.saveSetting("notifyOnIdleStop", checked) }
                }
                WrapCheckBox {
                    visible: root.supportsNotifications
                    text: i18n("Forgot to start tracking")
                    checked: root.notifyForgotToStart
                    onToggled: { root.notifyForgotToStart = checked; page.saveSetting("notifyForgotToStart", checked) }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing
                text: i18n("Settings sync with the Plasma widget via shared.json on the same machine.")
                wrapMode: Text.WordWrap
                color: KanteStyle.disabledTextColor
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing }
        }
    }

    // Pull to refresh (see shared/KantePullToRefresh.qml).
    KantePullToRefresh {
        parent: pageScroll
        anchors.fill: parent
        z: 10
        flickable: pageScroll.contentItem
        busy: root.isBusy
        onRefreshRequested: root.refreshAll()
    }
}
