import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/platform.js" as Platform

Kirigami.Page {
    id: page
    title: ""
    background: Rectangle { color: root.bgWindow }

    property int savedRefreshInterval: root.refreshInterval

    function saveSetting(key, value) {
        var patch = {}; patch[key] = value
        Platform.patchShared(null, root.currentConfig(), patch)
    }

    Flickable {
        anchors.fill: parent
        contentHeight: form.implicitHeight + 32
        clip: true
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: form
            width: parent.width - 32
            x: 16; spacing: 12

            Kirigami.Heading { level: 1; text: i18n("Settings"); color: root.clrText }

            QQC2.Label { Layout.fillWidth: true; text: i18n("Refresh interval"); font.bold: true; color: root.clrText }
            RowLayout { Layout.fillWidth: true
                QQC2.SpinBox {
                    id: refreshSpin
                    Layout.preferredWidth: 140
                    from: 5; to: 300; stepSize: 5
                    value: root.refreshInterval
                    textFromValue: function(value) { return value + "s" }
                    onValueChanged: {
                        root.refreshInterval = value
                        saveSetting("refreshInterval", value)
                    }
                }
                QQC2.Label { text: i18n("How often to poll the server"); color: root.clrTextMuted; elide: Text.ElideRight; Layout.fillWidth: true }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.clrSeparator }

            QQC2.Label { Layout.fillWidth: true; text: i18n("Work hours"); font.bold: true; color: root.clrText }

            // ── Begin ──
            QQC2.Label { text: i18n("Begin"); color: root.clrTextSec }
            QQC2.TextField {
                Layout.fillWidth: true
                text: root.workDayBegin
                placeholderText: "09:00"
                color: root.clrText; placeholderTextColor: root.clrTextMuted
                onEditingFinished: { root.workDayBegin = text; saveSetting("workDayBegin", text) }
            }

            // ── End ──
            QQC2.Label { text: i18n("End"); color: root.clrTextSec }
            QQC2.TextField {
                Layout.fillWidth: true
                text: root.workDayEnd
                placeholderText: "17:00"
                color: root.clrText; placeholderTextColor: root.clrTextMuted
                onEditingFinished: { root.workDayEnd = text; saveSetting("workDayEnd", text) }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.clrSeparator }

            QQC2.Label { Layout.fillWidth: true; text: i18n("Display"); font.bold: true; color: root.clrText }

            QQC2.CheckBox {
                Layout.fillWidth: true
                checked: root.showWorkSummary
                text: i18n("Show work summary (today / week totals)")
                onToggled: { root.showWorkSummary = checked; saveSetting("popupShowWorkSummary", checked) }
            }

            QQC2.CheckBox {
                Layout.fillWidth: true
                checked: root.showRecent
                text: i18n("Show recent entries")
                onToggled: { root.showRecent = checked; saveSetting("popupShowRecent", checked) }
            }

            QQC2.CheckBox {
                Layout.fillWidth: true
                checked: root.showFavorites
                text: i18n("Show favorites")
                onToggled: { root.showFavorites = checked; saveSetting("popupShowFavorites", checked) }
            }

            RowLayout { Layout.fillWidth: true
                QQC2.Label { text: i18n("Recent entries:"); color: root.clrText }
                QQC2.SpinBox { Layout.preferredWidth: 140; from: 3; to: 50; value: root.recentCount
                    textFromValue: function(v) { return v }
                    onValueChanged: { root.recentCount = value; saveSetting("recentCount", value) }
                }
                Item { Layout.fillWidth: true }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.clrSeparator }

            QQC2.CheckBox {
                Layout.fillWidth: true
                checked: root.confirmBeforeStop
                text: i18n("Confirm before stopping tracking")
                onToggled: { root.confirmBeforeStop = checked; saveSetting("confirmBeforeStop", checked) }
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Settings sync with the Plasma widget via shared.json on the same machine.")
                wrapMode: Text.WordWrap
                color: root.clrTextMuted
            }
        }
    }
}
