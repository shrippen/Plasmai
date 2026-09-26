import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "."

/**
 * Push button of the popup views.
 *   System  a plain Plasma button (unchanged).
 *   Kante   square, uppercase Rajdhani, thin frame; `emphasis` fills it with
 *           the accent (primary action) or the negative color (stop, delete).
 *
 * In Kante the Plasma frame and content stay (they size the button) but are
 * hidden; frame, icon and text are drawn here, so disabled buttons fade
 * instead of taking the Plasma theme's disabled colors.
 */
PlasmaComponents3.Button {
    id: control

    enum Emphasis {
        Normal,
        Primary,
        Destructive
    }

    property int emphasis: PButton.Emphasis.Normal

    readonly property bool filled: emphasis !== PButton.Emphasis.Normal
    readonly property color kanteFill: emphasis === PButton.Emphasis.Primary ? Style.accentColor
        : (emphasis === PButton.Emphasis.Destructive ? Style.negativeTextColor : "transparent")
    readonly property color kanteInk: filled ? Style.accentForegroundColor : Style.textColor

    Rectangle {
        z: -1
        anchors.fill: parent
        visible: Style.kante
        opacity: control.enabled ? 1 : 0.45
        color: {
            if (control.filled) {
                return control.down ? Qt.darker(control.kanteFill, 1.15) : control.kanteFill
            }
            return (control.down || control.hovered || control.checked) ? Style.sunkenColor : "transparent"
        }
        border.width: control.filled ? 0 : 1
        border.color: control.visualFocus ? Style.accentColor : Style.frameColor
    }

    RowLayout {
        visible: Style.kante
        x: control.leftPadding + Math.max(0, (control.availableWidth - width) / 2)
        y: control.topPadding
        width: Math.min(implicitWidth, control.availableWidth)
        height: control.availableHeight
        spacing: Math.max(control.spacing, Kirigami.Units.smallSpacing)
        opacity: control.enabled ? 1 : 0.5

        Kirigami.Icon {
            readonly property var iconSource: control.icon.name !== "" ? control.icon.name : control.icon.source
            visible: control.display !== T.AbstractButton.TextOnly && String(iconSource).length > 0
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            Layout.alignment: Qt.AlignVCenter
            source: iconSource
            color: control.kanteInk
            isMask: true
        }

        PlasmaComponents3.Label {
            visible: control.display !== T.AbstractButton.IconOnly && control.text.length > 0
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: control.text
            font: control.font
            color: control.kanteInk
            elide: Text.ElideRight
        }
    }

    Binding {
        target: control.background
        property: "opacity"
        value: 0
        when: Style.kante && control.background !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control.contentItem
        property: "opacity"
        value: 0
        when: Style.kante && control.contentItem !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: control
        property: "font"
        value: Style.headingFont(Style.defaultFont.pointSize)
        when: Style.kante
        restoreMode: Binding.RestoreBindingOrValue
    }
}
