import QtQuick
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.components as PlasmaComponents3
import "."

/**
 * Heading of the popup views.
 *   System  PlasmaExtras.Heading (unchanged).
 *   Kante   level 4 and below (sections): small uppercase monospace label
 *           followed by a thin rule; above: uppercase Rajdhani title.
 */
PlasmaExtras.Heading {
    id: control

    readonly property bool sectionLabel: level >= 4

    // Kante draws its own text over the hidden original; the heading's own font
    // and color stay untouched, so switching back to System restores them exactly.
    PlasmaComponents3.Label {
        id: kanteText
        visible: Style.kante
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, control.width)
        text: control.text
        font: control.sectionLabel ? Style.labelFont()
                                   : Style.headingFont(Style.defaultFont.pointSize * (control.level <= 2 ? 1.6 : 1.3))
        color: control.sectionLabel ? Style.mutedTextColor : Style.strongTextColor
        elide: Text.ElideRight
    }

    Rectangle {
        visible: Style.kante && control.sectionLabel
        x: kanteText.width + Math.round(kanteText.font.pixelSize * 0.8)
        width: Math.max(0, control.width - x)
        height: 1
        anchors.verticalCenter: parent.verticalCenter
        color: Style.ruleColor
    }

    Binding {
        target: control
        property: "color"
        value: "transparent"
        when: Style.kante
        restoreMode: Binding.RestoreBindingOrValue
    }
}
