// Kirigami Theme shim (system colors)
pragma Singleton
import QtQuick
QtObject {
    readonly property color backgroundColor: Qt.rgba(0.1, 0.1, 0.1, 1)
    readonly property color textColor: Qt.rgba(0.95, 0.95, 0.95, 1)
    readonly property color disabledTextColor: Qt.rgba(0.5, 0.5, 0.5, 1)
    readonly property color highlightColor: "#3daee9"
    readonly property color highlightedTextColor: "#fcfcfc"
    readonly property color positiveTextColor: "#27ae60"
    readonly property color neutralTextColor: "#f67400"
    readonly property color negativeTextColor: "#da4453"
    readonly property color linkColor: "#1d99f3"
    readonly property color activeTextColor: "#fcfcfc"
    readonly property color buttonHoverColor: "#3daee9"
    readonly property color buttonFocusColor: "#3daee9"
    readonly property color selectionColor: "#3daee9"
    readonly property color selectionTextColor: "#fcfcfc"
    readonly property color alternateBackgroundColor: Qt.rgba(0.15, 0.15, 0.15, 1)
    readonly property font defaultFont: Font { }
    readonly property font smallFont: Font { pointSize: defaultFont.pointSize - 2 }
}
