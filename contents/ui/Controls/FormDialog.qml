import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../Kante"

// Modal form dialog with OK and Cancel, see Label.qml. The children are the form
// (a column); acceptEnabled gates OK. Here Qt's standard buttons, translated by
// the desktop's Qt catalogs; the app has its own translated footer actions.
KanteDialog {
    id: dialog

    property bool acceptEnabled: true
    default property alias formData: form.data

    modal: true
    standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
    padding: Kirigami.Units.largeSpacing

    contentItem: ColumnLayout {
        id: form
        spacing: Kirigami.Units.mediumSpacing
    }

    // standardButton() has no binding: follow acceptEnabled and each opening.
    function syncOk() {
        var ok = dialog.standardButton(QQC2.Dialog.Ok)
        if (ok) {
            ok.enabled = dialog.acceptEnabled
        }
    }
    onAcceptEnabledChanged: syncOk()
    onAboutToShow: Qt.callLater(syncOk)
}
