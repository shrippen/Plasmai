import QtQuick
import "."

/**
 * Kante look for a Kirigami or QQC2 dialog: place one inside the
 * dialog. Replaces the background with a cut-corner card and hands the Kante
 * colors to the dialog's content; does nothing in the System style.
 */
// A QtObject, not an Item: inside a Kirigami.Dialog every item child counts as
// content, and its ScrollView sizes itself only from a single one.
QtObject {
    id: skin

    required property var dialog

    readonly property KanteScope scope: KanteScope { target: skin.dialog ? skin.dialog.contentItem : null }

    // Only handed to `background` while Kante is on.
    readonly property Item kanteBackground: KanteCard {
        color: KanteStyle.dialogColor
        barColor: KanteStyle.accentColor
    }

    readonly property Binding backgroundBinding: Binding {
        target: skin.dialog
        property: "background"
        value: skin.kanteBackground
        when: KanteStyle.themed && skin.dialog !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
}
