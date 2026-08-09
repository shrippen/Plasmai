import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi

/**
 * Stacked vertical bars — one column per day, segments colored by project.
 * days: [{ label, totalSeconds, stacks: [{ seconds, color, name }] }, ...]
 */
Item {
    id: root

    property var days: []
    property int barMaxHeight: Kirigami.Units.gridUnit * 5
    property string emptyText: ""
    property int gridLineCount: 4

    readonly property int maxSeconds: {
        var m = 0
        for (var i = 0; i < (days || []).length; i++) {
            m = Math.max(m, Number(days[i].totalSeconds) || 0)
        }
        return m
    }

    readonly property int axisWidth: Kirigami.Units.gridUnit * 2.4

    implicitHeight: barMaxHeight + Kirigami.Units.gridUnit * 1.6
    implicitWidth: Kirigami.Units.gridUnit * 16

    PlasmaComponents3.Label {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.axisWidth / 2
        visible: root.maxSeconds <= 0
        opacity: 0.6
        text: root.emptyText
    }

    PlasmaComponents3.Label {
        anchors.left: parent.left
        anchors.top: parent.top
        width: root.axisWidth
        visible: root.maxSeconds > 0
        horizontalAlignment: Text.AlignRight
        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
        opacity: 0.55
        elide: Text.ElideRight
        text: i18n("Time")
    }

    Item {
        id: yAxis
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: Kirigami.Units.gridUnit * 0.85
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.gridUnit * 1.2
        width: root.axisWidth
        visible: root.maxSeconds > 0

        PlasmaComponents3.Label {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            horizontalAlignment: Text.AlignRight
            font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
            opacity: 0.65
            elide: Text.ElideRight
            text: KimaiApi.formatDurationShort(root.maxSeconds)
        }
        PlasmaComponents3.Label {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
            opacity: 0.65
            elide: Text.ElideRight
            text: KimaiApi.formatDurationShort(Math.round(root.maxSeconds / 2))
        }
        PlasmaComponents3.Label {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            horizontalAlignment: Text.AlignRight
            font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
            opacity: 0.65
            text: "0"
        }
    }

    Item {
        id: plot
        anchors.left: yAxis.right
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.right: parent.right
        anchors.top: yAxis.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.gridUnit * 1.2
        visible: root.maxSeconds > 0

        Repeater {
            model: root.gridLineCount + 1
            delegate: Rectangle {
                width: plot.width
                height: 1
                y: plot.height * (index / root.gridLineCount)
                color: Kirigami.Theme.textColor
                opacity: index === root.gridLineCount ? 0.22 : 0.1
            }
        }

        Row {
            id: cols
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: root.days

                delegate: Item {
                    id: dayCol
                    property var day: modelData

                    width: Math.max(8, (cols.width - Math.max(0, root.days.length - 1) * cols.spacing)
                                    / Math.max(1, root.days.length))
                    height: cols.height

                    readonly property int colHeight: root.maxSeconds > 0
                        ? Math.round(height * ((day && day.totalSeconds) || 0) / root.maxSeconds)
                        : 0

                    readonly property var stackModel: {
                        var s = (dayCol.day && dayCol.day.stacks) ? dayCol.day.stacks : []
                        var rev = []
                        for (var i = s.length - 1; i >= 0; i--) {
                            rev.push(s[i])
                        }
                        return rev
                    }

                    Column {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(4, parent.width * 0.55)
                        spacing: 0

                        Repeater {
                            model: dayCol.stackModel
                            delegate: Rectangle {
                                property var stack: modelData
                                width: parent.width
                                height: {
                                    var total = (dayCol.day && dayCol.day.totalSeconds) || 0
                                    if (total <= 0 || dayCol.colHeight <= 0) {
                                        return 0
                                    }
                                    return Math.max(1, Math.round(dayCol.colHeight * (stack.seconds / total)))
                                }
                                color: (stack && stack.color) ? stack.color : Kirigami.Theme.highlightColor
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -Kirigami.Units.gridUnit * 1.1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                        opacity: 0.7
                        text: (dayCol.day && dayCol.day.label) ? dayCol.day.label : ""
                    }
                }
            }
        }
    }
}
