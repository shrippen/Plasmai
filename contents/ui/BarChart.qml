import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi

/**
 * Simple vertical bar chart with a labeled Y axis (duration) and faint grid.
 * model: [{ label, seconds, color? }, ...]
 */
Item {
    id: root

    property var model: []
    property int barMaxHeight: Kirigami.Units.gridUnit * 5
    property bool showValues: false
    property string emptyText: ""
    property int gridLineCount: 4

    readonly property int maxSeconds: {
        var m = 0
        for (var i = 0; i < (model || []).length; i++) {
            m = Math.max(m, Number(model[i].seconds) || 0)
        }
        return m
    }

    readonly property int axisWidth: Kirigami.Units.gridUnit * 2.4

    implicitHeight: barMaxHeight + Kirigami.Units.gridUnit * 1.6
    implicitWidth: Kirigami.Units.gridUnit * 16

    PlasmaComponents3.Label {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.axisWidth / 2
        visible: !root.model || root.model.length === 0 || root.maxSeconds <= 0
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

        // Faint horizontal grid lines
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
            id: barsRow
            anchors.fill: parent
            spacing: 2

            Repeater {
                model: root.model
                delegate: Item {
                    width: Math.max(2, (barsRow.width - Math.max(0, root.model.length - 1) * barsRow.spacing) / Math.max(1, root.model.length))
                    height: barsRow.height

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(2, parent.width * 0.7)
                        height: root.maxSeconds > 0
                                ? Math.max(modelData.seconds > 0 ? 2 : 0,
                                           Math.round(parent.height * (modelData.seconds / root.maxSeconds)))
                                : 0
                        radius: 1
                        color: modelData.color || Kirigami.Theme.highlightColor
                        opacity: modelData.seconds > 0 ? 1 : 0.15
                    }

                    PlasmaComponents3.Label {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -Kirigami.Units.gridUnit * 1.1
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Do not bind width to the narrow bar — that forces "…"
                        horizontalAlignment: Text.AlignHCenter
                        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                        opacity: 0.7
                        elide: Text.ElideNone
                        clip: false
                        z: 1
                        text: modelData.label || ""
                    }
                }
            }
        }
    }
}
