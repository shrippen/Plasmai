import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Kante"

// The app's form dialog (see Button.qml): Kirigami's dialog with Save and Cancel as
// own footer actions, since Qt's standard button texts stay English on Android (no
// Qt catalogs there). Same API as the Plasmoid's: the children are the form (a
// column), acceptEnabled gates Save.
Kirigami.Dialog {
    id: dialog

    property bool acceptEnabled: true
    default property alias formData: form.data

    KanteDialogSkin { dialog: dialog }

    standardButtons: Kirigami.Dialog.NoButton
    customFooterActions: [
        Kirigami.Action {
            text: i18n("Save")
            icon.name: "dialog-ok"
            enabled: dialog.acceptEnabled
            onTriggered: dialog.accept()
        },
        Kirigami.Action {
            text: i18n("Cancel")
            icon.name: "dialog-cancel"
            onTriggered: dialog.reject()
        }
    ]
    padding: Kirigami.Units.largeSpacing

    ColumnLayout {
        id: form
        spacing: Kirigami.Units.mediumSpacing
    }
}
