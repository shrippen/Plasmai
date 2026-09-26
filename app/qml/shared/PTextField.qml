import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "."

/**
 * Text field of the popup views.
 *   System  a plain text field (unchanged, including custom backgrounds).
 *   Kante   square sunken box with a thin frame; the frame turns accent on focus.
 */
QQC2.TextField {
    id: control

    /** Kante: draw the sunken box (false inside an already framed container). */
    property bool kanteFrame: true

    Rectangle {
        z: -1
        anchors.fill: parent
        visible: Style.kante && control.kanteFrame
        color: Style.sunkenColor
        opacity: control.enabled ? 1 : 0.5
        border.width: 1
        border.color: control.activeFocus ? Style.accentColor : Style.frameColor
    }

    Binding {
        target: control.background
        property: "opacity"
        value: 0
        when: Style.kante && control.background !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control
        property: "color"
        value: Style.textColor
        when: Style.kante
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control
        property: "placeholderTextColor"
        value: Style.disabledTextColor
        when: Style.kante
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control
        property: "selectionColor"
        value: Style.accentColor
        when: Style.kante
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control
        property: "selectedTextColor"
        value: Style.accentForegroundColor
        when: Style.kante
        restoreMode: Binding.RestoreBindingOrValue
    }
}
