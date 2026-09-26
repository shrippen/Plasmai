import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Kante"

/**
 * CheckBox whose label wraps instead of being clipped. Long labels (settings hints,
 * translations) otherwise run out of the page on narrow phone screens.
 */
QQC2.CheckBox {
    KanteCheckSkin { control: parent }
    id: control

    Layout.fillWidth: true

    contentItem: QQC2.Label {
        text: control.text
        wrapMode: Text.Wrap
        verticalAlignment: Text.AlignVCenter
        opacity: control.enabled ? 1 : 0.5
        leftPadding: control.indicator ? control.indicator.width + control.spacing : 0
    }
}
