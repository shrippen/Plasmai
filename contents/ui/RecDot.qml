import QtQuick
import org.kde.kirigami as Kirigami
import "Kante"

/** Red "recording" dot of the panel's timer indicator. */
Rectangle {
    implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.45)
    implicitHeight: implicitWidth
    // Kante: markers are squares.
    radius: KanteStyle.active ? 0 : width / 2
    color: KanteStyle.negativeTextColor
}
