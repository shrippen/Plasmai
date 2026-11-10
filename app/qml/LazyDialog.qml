import QtQuick

/**
 * A dialog built when it is first opened, not with its page. The timer page held six dialogs
 * nobody had asked for yet, each with Material's shadows; with the edit form and the "start
 * something else" pickers and the drawer's entries they cost the Android start a fifth (Pixel 6,
 * warm start: data shown after 1.69 s, built when needed 1.35 s).
 *
 *     LazyDialog {
 *         id: deleteDialog
 *         sourceComponent: Component { Kirigami.PromptDialog { id: deletePrompt; property var target ... } }
 *     }
 *     deleteDialog.open({ target: entry })          // builds it once, sets target, opens it
 *     const d = deleteDialog.build(); d.reset()     // the dialog itself, built if needed
 *
 * Give the dialog inside its own id: the Loader's id is visible there too.
 */
Loader {
    id: lazy

    active: false

    /** The dialog, built the first time. */
    function build() {
        active = true
        return item
    }

    /** Opens the dialog; `props` (optional) are set on it first. */
    function open(props) {
        const dialog = build()
        const values = props || {}
        for (const key in values) {
            dialog[key] = values[key]
        }
        dialog.open()
    }
}
