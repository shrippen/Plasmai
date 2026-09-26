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

    Binding { target: scope.theme; property: "inherit"; value: false; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "textColor"; value: KanteStyle.textColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "disabledTextColor"; value: KanteStyle.disabledTextColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "backgroundColor"; value: KanteStyle.dialogColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "alternateBackgroundColor"; value: KanteStyle.cardColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "highlightColor"; value: KanteStyle.accentColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "highlightedTextColor"; value: KanteStyle.accentForegroundColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "focusColor"; value: KanteStyle.accentColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "hoverColor"; value: KanteStyle.accentColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "linkColor"; value: KanteStyle.infoColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "positiveTextColor"; value: KanteStyle.positiveTextColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "neutralTextColor"; value: KanteStyle.neutralTextColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
    Binding { target: scope.theme; property: "negativeTextColor"; value: KanteStyle.negativeTextColor; when: KanteStyle.themed && scope.theme !== null; restoreMode: Binding.RestoreBindingOrValue }
}
