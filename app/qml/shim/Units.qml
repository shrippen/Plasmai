// Kirigami Units shim
pragma Singleton
import QtQuick
QtObject {
    readonly property real gridUnit: 20
    readonly property real largeSpacing: 16
    readonly property real smallSpacing: 4
    readonly property real hugeSpacing: 32
    readonly property real iconSizes: QtObject {
        readonly property int small: 16
        readonly property int medium: 22
        readonly property int large: 32
    }
    readonly property real toolTipDelay: 700
}
