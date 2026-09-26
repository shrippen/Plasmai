import QtQuick
import org.kde.kirigami as Kirigami
import "."

/**
 * Hands the Kante colors to `target`'s Kirigami.Theme, so Plasma and
 * Kirigami controls below it (labels, check boxes, spin boxes, combo
 * boxes, icons) follow Kante too. Does nothing in the System style: the
 * bindings restore the Plasma theme when Kante is switched off.
 *
 * Place one inside the popup root and inside each popup/dialog (popups do
 * not inherit the theme of the item that opens them).
 */
Item {
    id: scope

    required property Item target
    readonly property var theme: target ? target.Kirigami.Theme : null

    visible: false

    Binding { target: scope.theme; property: "inherit"; value: false; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "textColor"; value: Style.textColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "disabledTextColor"; value: Style.disabledTextColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "backgroundColor"; value: Style.dialogColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "alternateBackgroundColor"; value: Style.cardColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "highlightColor"; value: Style.accentColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "highlightedTextColor"; value: Style.accentForegroundColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "focusColor"; value: Style.accentColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "hoverColor"; value: Style.accentColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "linkColor"; value: Style.infoColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "positiveTextColor"; value: Style.positiveTextColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "neutralTextColor"; value: Style.neutralTextColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "negativeTextColor"; value: Style.negativeTextColor; when: Style.kante && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
}
