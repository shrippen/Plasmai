import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Controls" as Controls
import "../code/kimaiApi.js" as KimaiApi
import "Kante"

/**
 * Pie chart + legend. Kante has no pie: there each row is a bar in its colour
 * (KanteBarChart, hours on the axis) over the same legend.
 * rows: [{ name, seconds, color, ratio }, ...]
 */
ColumnLayout {
    id: root

    property var rows: []
    property int totalSeconds: 0
    property string title: ""
    property string emptyText: ""
    property int chartSize: Kirigami.Units.gridUnit * 7
    readonly property int secondsPerHour: 3600

    spacing: Kirigami.Units.smallSpacing

    Controls.Label {
        Layout.fillWidth: true
        visible: root.title.length > 0 || (KanteStyle.active && root.totalSeconds > 0)
        // Kante: the total moves from the donut's hole to the title ("Today · 5:30").
        text: KanteStyle.active && root.totalSeconds > 0
              ? [root.title, KimaiApi.formatDurationShort(root.totalSeconds)].filter(function(t) { return t.length > 0 }).join(" · ")
              : root.title
        font.bold: true
        opacity: 0.85
    }

    // Kante: one bar per row; a row's hours sit at its own index, so it takes its colour.
    KanteBarChart {
        Layout.fillWidth: true
        Layout.preferredHeight: root.chartSize
        visible: KanteStyle.active && root.totalSeconds > 0
        axis: true
        valueFormat: KanteBarChart.ValueFormat.Hours
        values: (root.rows || []).map(function(row, i) {
            return root.rows.map(function(other, k) { return k === i ? (Number(row.seconds) || 0) / root.secondsPerHour : 0 })
        })
        stackColors: (root.rows || []).map(function(row) { return row.color || PlasmaiColors.chart })
        partNames: (root.rows || []).map(function(row) {
            // statsData.js has no i18n; its catch-all row is keyed "_other".
            return row.key === "_other" ? i18n("Other") : (row.name || "")
        })
    }

    // Empty: the chart's height, so an empty pie keeps its place next to a full one.
    Controls.Label {
        Layout.fillWidth: true
        Layout.preferredHeight: root.chartSize
        visible: KanteStyle.active && root.totalSeconds <= 0
        opacity: 0.6
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.emptyText
    }

    Item {
        visible: !KanteStyle.active
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: root.chartSize
        Layout.preferredHeight: root.chartSize

        Controls.Label {
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
                    ctx.fillStyle = rows[i].color || PlasmaiColors.chart
                    ctx.arc(cx, cy, r, start, start + slice, false)
                    ctx.closePath()
                    ctx.fill()
                    start += slice
                }
                // Donut hole for readability in a small plasmoid
                ctx.beginPath()
                ctx.fillStyle = KanteStyle.backgroundColor
                ctx.arc(cx, cy, r * 0.45, 0, Math.PI * 2, false)
                ctx.fill()
            }
        }

        Controls.Label {
            anchors.centerIn: parent
            visible: root.totalSeconds > 0
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: KanteStyle.smallFont.pointSize
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
                CustomerColorDot {
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    customerColor: modelData.color || PlasmaiColors.entityFallback
                    sizeFactor: 0.55
                    slotSizeFactor: 0.7
                }
                Controls.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pointSize: KanteStyle.smallFont.pointSize
                    // statsData.js has no i18n; its catch-all row is keyed "_other".
                    text: modelData.key === "_other" ? i18n("Other") : modelData.name
                }
                Controls.Label {
                    font.pointSize: KanteStyle.smallFont.pointSize
                    opacity: 0.75
                    text: KimaiApi.formatDurationShort(modelData.seconds)
                }
            }
        }
    }
}
