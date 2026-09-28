import QtQuick
import org.kde.kirigami as Kirigami
import "Kante"

/** Red "recording" dot of the panel's timer indicator. */
Rectangle {
    implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.45)
    implicitHeight: implicitWidth
    radius: width / 2
    color: KanteStyle.negativeTextColor
}
