import QtQuick
import "Kante"

/**
 * Red edge of the panel's timer indicator, drawn inside its parent: a line along the bottom
 * (mode 1) or a stripe along the left side (mode 2). Mode 0 (dot) draws nothing here.
 */
Rectangle {
    property int mode: 0
    property bool active: true

    visible: active && (mode === 1 || mode === 2)
    color: KanteStyle.negativeTextColor
    x: 0
    y: mode === 1 ? parent.height - height : 0
    width: mode === 1 ? parent.width : 3
    height: mode === 1 ? 2 : parent.height
}
