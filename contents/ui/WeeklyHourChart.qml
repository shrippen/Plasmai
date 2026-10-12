import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Controls" as Controls
import "../code/kimaiApi.js" as KimaiApi
import "."
import "Kante"

/**
 * Weekly hour timeline — one horizontal row per day.
 * days: [{ label, totalSeconds, segments: [{ startHour, endHour, color, name, seconds }] }]
 * hourMin / hourMax: visible window on the 0–24h axis.
 */
ColumnLayout {
    id: root

    property var days: []
    property real hourMin: 0
    property real hourMax: 24
    property string emptyText: ""
    property int gridLineCount: 4

    readonly property real hourSpan: Math.max(1, hourMax - hourMin)
    readonly property bool hasData: {
        for (var i = 0; i < (days || []).length; i++) {
            if ((days[i].totalSeconds || 0) > 0) {
                return true
            }
        }
        return false
    }

    readonly property int labelWidth: Kirigami.Units.gridUnit * 2.2
    readonly property int rowHeight: Kirigami.Units.gridUnit * 1.2
    readonly property var hourLabels: {
        var labels = []
        var span = root.hourSpan
        var steps = Math.min(6, Math.max(2, Math.round(span / 2)))
        for (var i = 0; i <= steps; i++) {
            var h = root.hourMin + (span * i / steps)
            labels.push({
                ratio: i / steps,
                text: (Math.round(h) < 10 ? "0" : "") + Math.round(h)
            })
        }
        return labels
    }

    // Kante hour heads: every 2 h on a work day, every 6 h past 12 h.
    readonly property real wideSpanHours: 12
    readonly property real wideTickHours: 6
    readonly property real narrowTickHours: 2

    /** Kante: segments as KanteWeekTimeline entries {day, start, end, color, title, seconds}. */
    readonly property var timelineEntries: {
        var out = []
        for (var i = 0; i < (days || []).length; i++) {
            var segments = days[i].segments || []
            for (var k = 0; k < segments.length; k++) {
                var seg = segments[k]
                out.push({ day: i, start: seg.startHour, end: seg.endHour, color: seg.color,
                           title: seg.name || "", seconds: seg.seconds || 0 })
            }
        }
        return out
    }

    /** Kante: row of today (-1: not this week) and now in hours. */
    readonly property int todayRow: {
        var today = new Date().toDateString()
        for (var i = 0; i < (days || []).length; i++) {
            if (days[i].date && new Date(days[i].date).toDateString() === today) {
                return i
            }
        }
        return -1
    }
    readonly property real nowHours: {
        var now = new Date()
        return now.getHours() + now.getMinutes() / 60
    }

    spacing: Kirigami.Units.smallSpacing / 2

    Controls.Label {
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        visible: !root.hasData
        opacity: 0.6
        text: root.emptyText
    }

    // Hour axis
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.85
        Layout.leftMargin: root.labelWidth + Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.gridUnit * 2.2 + Kirigami.Units.smallSpacing
        visible: root.hasData && !KanteStyle.active

        Repeater {
            model: root.hourLabels
            delegate: Controls.Label {
                property var labelData: modelData
                y: 0
                x: {
                    if (!parent) {
                        return 0
                    }
                    if (labelData.ratio <= 0.01) {
                        return 0
                    }
                    if (labelData.ratio >= 0.99) {
                        return parent.width - width
                    }
                    return parent.width * labelData.ratio - width / 2
                }
                font.pointSize: KanteStyle.smallFont.pointSize - 1
                opacity: 0.65
                text: labelData.text
            }
        }
    }

    // Kante: a KanteWeekTimeline; hovering (on touch tapping) a block shows its project, span and duration.
    KanteWeekTimeline {
        id: kanteTimeline
        Layout.fillWidth: true
        visible: KanteStyle.active && root.hasData
        dayNames: (root.days || []).map(function(day) { return day.label || "" })
        spanFrom: root.hourMin
        spanTo: root.hourMax
        tickStep: root.hourSpan > root.wideSpanHours ? root.wideTickHours : root.narrowTickHours
        entries: root.timelineEntries
        today: root.todayRow
        now: root.todayRow >= 0 ? root.nowHours : -1
    }

    Repeater {
        model: root.hasData && !KanteStyle.active ? root.days : []
        delegate: RowLayout {
            id: dayRow
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            property var day: modelData

            Controls.Label {
                Layout.preferredWidth: root.labelWidth
                Layout.maximumWidth: root.labelWidth
                elide: Text.ElideRight
                font.pointSize: KanteStyle.smallFont.pointSize
                opacity: 0.8
                text: (dayRow.day && dayRow.day.label) ? dayRow.day.label : ""
            }

            Item {
                id: track
                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight

                Repeater {
                    model: root.gridLineCount + 1
                    delegate: Rectangle {
                        width: 1
                        height: track.height
                        x: track.width * (index / root.gridLineCount)
                        color: KanteStyle.textColor
                        opacity: index === 0 || index === root.gridLineCount ? 0.18 : 0.08
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: KanteStyle.textColor
                    opacity: 0.12
                }

                Repeater {
                    model: (dayRow.day && dayRow.day.segments) ? dayRow.day.segments : []
                    delegate: Item {
                        id: segItem
                        property var seg: modelData
                        x: Math.max(0, track.width * ((seg.startHour - root.hourMin) / root.hourSpan))
                        width: Math.max(2, track.width * ((seg.endHour - seg.startHour) / root.hourSpan))
                        height: Math.max(8, track.height * 0.72)
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: (segItem.seg && segItem.seg.color)
                                   ? segItem.seg.color
                                   : KanteStyle.highlightColor
                            opacity: 0.92
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -TouchUi.chartHitSlop
                            hoverEnabled: true
                            acceptedButtons: TouchUi.active ? Qt.LeftButton : Qt.NoButton
                            property bool tipPinned: false
                            onClicked: tipPinned = !tipPinned
                            onExited: tipPinned = false
                            Controls.ToolTip.visible: containsMouse || tipPinned
                            Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                            Controls.ToolTip.text: segItem.seg
                                ? (segItem.seg.name + " · "
                                   + KimaiApi.formatDurationShort(segItem.seg.seconds))
                                : ""
                        }
                    }
                }
            }

            Controls.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.2
                horizontalAlignment: Text.AlignRight
                font.pointSize: KanteStyle.smallFont.pointSize - 1
                opacity: 0.7
                text: dayRow.day && dayRow.day.totalSeconds > 0
                      ? KimaiApi.formatDurationShort(dayRow.day.totalSeconds)
                      : ""
            }
        }
    }
}
