import QtQuick
import "."

/**
 * Kante look for a menu or other popup: place inside it. Replaces the
 * background with a nearly opaque cut-corner card and hands the Kante colors
 * to the content (menu items). Nothing in the System style.
 */
Item {
    id: skin

    required property var popup

    visible: false

    StyleScope { target: skin.popup ? skin.popup.contentItem : null }

    // Not a child: only handed to `background` while Kante is on.
    readonly property Item kanteBackground: KanteCard {
        color: Style.dialogColor
        borderColor: Style.frameColor
        chamfer: Style.smallChamfer
    }

    Binding {
        target: skin.popup
        property: "background"
        value: skin.kanteBackground
        when: Style.kante && skin.popup !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
}
