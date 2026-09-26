import QtQuick
import QtQuick.Controls as QQC2
import "."

/**
 * Kante title for a Kirigami page header: place inside the page. Uppercase
 * Rajdhani instead of the style's heading; nothing in the System style.
 */
Item {
    id: skin

    required property var page

    visible: false

    readonly property Component kanteTitle: Component {
        QQC2.Label {
            text: skin.page ? skin.page.title : ""
            font: Style.headingFont(Style.defaultFont.pointSize * 1.35)
            color: Style.strongTextColor
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    Binding {
        target: skin.page
        property: "titleDelegate"
        value: skin.kanteTitle
        when: Style.kante && skin.page !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
}
