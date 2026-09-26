import QtQuick
import org.kde.kirigami as Kirigami
import "."

/**
 * Kante look for input controls that keep their own content (spin box,
 * combo box, text area): place inside the control. Hides the style's
 * background and draws a square sunken box whose frame turns accent on
 * focus. Nothing in the System style.
 */
Rectangle {
    id: skin

    required property Item control

    z: -1
    anchors.fill: parent
    visible: KanteStyle.themed
    color: KanteStyle.sunkenColor
    opacity: control && control.enabled ? 1 : 0.5
    border.width: 1
    border.color: control && (control.activeFocus || control.visualFocus) ? KanteStyle.accentColor : KanteStyle.frameColor

    Binding {
        target: skin.control ? skin.control.background : null
        property: "opacity"
        value: 0
        when: KanteStyle.themed && skin.control !== null && skin.control.background !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
    // Combo boxes: draw the shown value over the hidden content item instead of
    // recoloring it, so switching back to System leaves the style's text untouched.
    readonly property bool comboBox: control !== null && control.displayText !== undefined

    Text {
        visible: KanteStyle.themed && skin.comboBox && skin.control.contentItem !== null
        x: skin.control && skin.control.contentItem ? skin.control.contentItem.x + (skin.control.contentItem.leftPadding || 0) : 0
        width: skin.control && skin.control.contentItem ? skin.control.contentItem.width - (skin.control.contentItem.leftPadding || 0) : 0
        anchors.verticalCenter: parent.verticalCenter
        text: skin.comboBox ? skin.control.displayText : ""
        font: skin.control ? skin.control.font : KanteStyle.defaultFont
        color: KanteStyle.textColor
        elide: Text.ElideRight
    }

    // Desktop styles paint the drop-down arrow into the hidden background: draw one.
    Kirigami.Icon {
        visible: KanteStyle.themed && skin.comboBox && (!skin.control.indicator || !skin.control.indicator.visible)
        width: Kirigami.Units.iconSizes.small
        height: width
        anchors.right: parent.right
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        source: "arrow-down"
        isMask: true
        color: KanteStyle.mutedTextColor
    }

    Binding {
        target: skin.control ? skin.control.contentItem : null
        property: "opacity"
        value: 0
        when: KanteStyle.themed && skin.comboBox && skin.control.contentItem !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
}
