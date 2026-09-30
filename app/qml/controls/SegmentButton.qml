import QtQuick
import org.kde.kirigami as Kirigami
import "../Kante"

// One segment of a segmented toggle (checkable, exclusive), see Button.qml.
// Kante and Material mark the checked segment with a tinted frame; other styles
// keep their own background (the desktop style draws the button's text there).
// A separate Binding, not "Binding on background": that form replaces the
// style's background even while inactive.
KanteToolButton {
    id: control

    Binding {
        target: control
        property: "background"
        when: KanteStyle.active || KanteStyle.materialStyle
        restoreMode: Binding.RestoreBindingOrValue
        value: Rectangle {
            radius: Kirigami.Units.smallSpacing
            color: control.checked ? KanteStyle.tint(KanteStyle.highlightColor, 0.18) : "transparent"
            border.width: control.checked ? 1 : 0
            border.color: KanteStyle.highlightColor
        }
    }
}
