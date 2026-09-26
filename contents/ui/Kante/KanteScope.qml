import QtQuick
import org.kde.kirigami as Kirigami
import "."

/**
 * Hands the Kante colors to `target`'s Kirigami.Theme, so Plasma and
 * Kirigami controls below it (labels, check boxes, spin boxes, combo
 * boxes, icons) follow Kante too. Does nothing in the System style: when
 * Kante is switched off the colors are reset and the target inherits again.
 *
 * Place one inside the popup root and inside each popup/dialog (popups do
 * not inherit the theme of the item that opens them).
 */
Item {
    id: scope

    required property Item target
    readonly property var theme: target ? target.Kirigami.Theme : null

    visible: false

    // Theme property -> KanteStyle role.
    readonly property var roles: ({
        textColor: "textColor",
        disabledTextColor: "disabledTextColor",
        backgroundColor: "dialogColor",
        alternateBackgroundColor: "cardColor",
        highlightColor: "accentColor",
        highlightedTextColor: "accentForegroundColor",
        focusColor: "accentColor",
        hoverColor: "accentColor",
        linkColor: "infoColor",
        positiveTextColor: "positiveTextColor",
        neutralTextColor: "neutralTextColor",
        negativeTextColor: "negativeTextColor"
    })

    // Kante: bind the roles. Otherwise reset (undefined) so the target inherits
    // again; a Binding would restore the old colors as fixed values, and the
    // controls below would keep them after the platform theme changes.
    function apply() {
        if (!theme || KanteStyle.materialStyle || KanteStyle.themed === applied) {
            return
        }
        for (var prop in roles) {
            theme[prop] = KanteStyle.themed ? Qt.binding(roleBinding(roles[prop])) : undefined
        }
        theme.inherit = !KanteStyle.themed
        applied = KanteStyle.themed
    }

    /** The colors are set by this scope (System never touches the target). */
    property bool applied: false

    function roleBinding(role) {
        return function() { return KanteStyle[role] }
    }

    onThemeChanged: {
        applied = false
        apply()
    }
    Component.onCompleted: apply()

    Connections {
        target: KanteStyle
        function onThemedChanged() { scope.apply() }
    }
}
