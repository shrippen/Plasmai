import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi

/**
 * Pie chart + legend.
 * rows: [{ name, seconds, color, ratio }, ...]
 */
ColumnLayout {
    id: root

    property var rows: []
    property int totalSeconds: 0
    property string title: ""
    property string emptyText: ""
    property int chartSize: Kirigami.Units.gridUnit * 7

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: root.title.length > 0
        text: root.title
        font.bold: true
        opacity: 0.85
    }

    Item {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: root.chartSize
        Layout.preferredHeight: root.chartSize

        PlasmaComponents3.Label {
            anchors.centerIn: parent
            visible: root.totalSeconds <= 0
            opacity: 0.6
            wrapMode: Text.WordWrap
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            text: root.emptyText
        }

        Canvas {
            id: pie
            anchors.fill: parent
            visible: root.totalSeconds > 0
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width
                var h = height
                var cx = w / 2
                var cy = h / 2
                var r = Math.min(w, h) / 2 - 2
                var rows = root.rows || []
                var start = -Math.PI / 2
                if (rows.length === 0) {
                    return
                }
                for (var i = 0; i < rows.length; i++) {
                    var slice = Math.max(0, Number(rows[i].ratio) || 0) * Math.PI * 2
                    if (slice <= 0) {
                        continue
                    }
                    ctx.beginPath()
                    ctx.moveTo(cx, cy)
                    ctx.fillStyle = rows[i].color || "#3584e4"
                    ctx.arc(cx, cy, r, start, start + slice, false)
                    ctx.closePath()
                    ctx.fill()
                    start += slice
                }
                // Donut hole for readability in a small plasmoid
                ctx.beginPath()
                ctx.fillStyle = Kirigami.Theme.backgroundColor
                ctx.arc(cx, cy, r * 0.45, 0, Math.PI * 2, false)
                ctx.fill()
            }
        }

        PlasmaComponents3.Label {
            anchors.centerIn: parent
            visible: root.totalSeconds > 0
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.bold: true
            text: KimaiApi.formatDurationShort(root.totalSeconds)
        }

        // Repaint when data changes
        Connections {
            target: root
            function onRowsChanged() { pie.requestPaint() }
            function onTotalSecondsChanged() { pie.requestPaint() }
        }
        Component.onCompleted: pie.requestPaint()
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: root.totalSeconds > 0

        Repeater {
            model: root.rows
            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 1
                    color: modelData.color || Kirigami.Theme.highlightColor
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: modelData.name
                }
                PlasmaComponents3.Label {
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.75
                    text: KimaiApi.formatDurationShort(modelData.seconds)
                }
            }
        }
    }
}
