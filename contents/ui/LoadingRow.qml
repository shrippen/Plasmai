import QtQuick
import org.kde.kirigami as Kirigami
import "Kante"

Row {
    id: root

    property int rowCount: 1

    spacing: Kirigami.Units.smallSpacing

    // Kante draws KanteSkeleton lines (they pulse on their own); System keeps the bars below.
    // Stable animated opacity; SequentialAnimation doesn't expose an
    // `opacity` property, so binding to it yields undefined warnings.
    opacity: KanteStyle.active ? 1 : animOpacity
    property real animOpacity: 0.25

    SequentialAnimation on animOpacity {
        id: pulse
        loops: Animation.Infinite
        // Must not run while hidden — keeps the animation driver awake in plasmashell.
        running: root.visible && !KanteStyle.active
        NumberAnimation { from: 0.25; to: 0.55; duration: 900 }
        NumberAnimation { from: 0.55; to: 0.25; duration: 900 }
    }

    KanteSkeleton {
        visible: KanteStyle.active
        lines: root.rowCount
        width: root.width
    }

    Repeater {
        model: KanteStyle.active ? 0 : root.rowCount

        Rectangle {
            width: index === 0 ? root.width * 0.65 : root.width * 0.35
            height: Kirigami.Units.gridUnit
            radius: Kirigami.Units.smallSpacing / 2
            color: KanteStyle.disabledTextColor
        }
    }
}
