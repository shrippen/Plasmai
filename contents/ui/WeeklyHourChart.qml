import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi
import "."

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

    spacing: Kirigami.Units.smallSpacing / 2

    PlasmaComponents3.Label {
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
        visible: root.hasData

        Repeater {
            model: root.hourLabels
            delegate: PlasmaComponents3.Label {
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
                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                opacity: 0.65
                text: labelData.text
            }
        }
    }

    Repeater {
        model: root.hasData ? root.days : []
        delegate: RowLayout {
            id: dayRow
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            property var day: modelData

            PlasmaComponents3.Label {
                Layout.preferredWidth: root.labelWidth
                Layout.maximumWidth: root.labelWidth
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
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
                        color: Kirigami.Theme.textColor
                        opacity: index === 0 || index === root.gridLineCount ? 0.18 : 0.08
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: Kirigami.Theme.textColor
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
                                   : Kirigami.Theme.highlightColor
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
                            PlasmaComponents3.ToolTip.visible: containsMouse || tipPinned
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                            PlasmaComponents3.ToolTip.text: segItem.seg
                                ? (segItem.seg.name + " · "
                                   + KimaiApi.formatDurationShort(segItem.seg.seconds))
                                : ""
                        }
                    }
                }
            }

            PlasmaComponents3.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.2
                horizontalAlignment: Text.AlignRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                opacity: 0.7
                text: dayRow.day && dayRow.day.totalSeconds > 0
                      ? KimaiApi.formatDurationShort(dayRow.day.totalSeconds)
                      : ""
            }
        }
    }
}
