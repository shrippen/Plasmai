import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "."

/**
 * Text field.
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
        visible: KanteStyle.themed && control.kanteFrame
        color: KanteStyle.sunkenColor
        opacity: control.enabled ? 1 : 0.5
        border.width: 1
        border.color: control.activeFocus ? KanteStyle.accentColor : KanteStyle.frameColor
    }

    Binding {
        target: control.background
        property: "opacity"
        value: 0
        when: KanteStyle.themed && control.background !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control
        property: "color"
        value: KanteStyle.textColor
        when: KanteStyle.themed
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control
        property: "placeholderTextColor"
        value: KanteStyle.disabledTextColor
        when: KanteStyle.themed
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control
        property: "selectionColor"
        value: KanteStyle.accentColor
        when: KanteStyle.themed
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control
        property: "selectedTextColor"
        value: KanteStyle.accentForegroundColor
        when: KanteStyle.themed
        restoreMode: Binding.RestoreBindingOrValue
    }
}
