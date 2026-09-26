import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "."

/**
 * Tool (icon) button of the popup views.
 *   System  a plain Plasma tool button (unchanged).
 *   Kante   square; hover and pressed show the sunken tint instead of the
 *           rounded Breeze highlight.
 */
PlasmaComponents3.ToolButton {
    id: control

    Rectangle {
        z: -1
        anchors.fill: parent
        visible: Style.kante && (control.hovered || control.down || control.checked || control.visualFocus)
        // Checked (segmented filters): accent fill like a primary button.
        color: control.checked ? Style.accentColor : Style.sunkenColor
        border.width: control.visualFocus && !control.checked ? 1 : 0
        border.color: Style.accentColor
    }

    Binding {
        target: control.Kirigami.Theme
        property: "textColor"
        value: Style.accentForegroundColor
        when: Style.kante && control.checked
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control.Kirigami.Theme
        property: "highlightedTextColor"
        value: Style.accentForegroundColor
        when: Style.kante && control.checked
        restoreMode: Binding.RestoreBindingOrValue
    }

    Binding {
        target: control.background
        property: "opacity"
        value: 0
        when: Style.kante && control.background !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
}
