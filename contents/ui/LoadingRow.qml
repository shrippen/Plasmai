import QtQuick
import org.kde.kirigami as Kirigami

Row {
    id: root

    property int rowCount: 1

    spacing: Kirigami.Units.smallSpacing

    opacity: pulse.opacity

    SequentialAnimation on opacity {
        id: pulse
        loops: Animation.Infinite
        running: true
        NumberAnimation { from: 0.25; to: 0.55; duration: 900 }
        NumberAnimation { from: 0.55; to: 0.25; duration: 900 }
    }

    Repeater {
        model: root.rowCount

        Rectangle {
            width: index === 0 ? root.width * 0.65 : root.width * 0.35
            height: Kirigami.Units.gridUnit
            radius: Kirigami.Units.smallSpacing / 2
            color: Kirigami.Theme.disabledTextColor
        }
    }
}
