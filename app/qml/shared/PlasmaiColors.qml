pragma Singleton
import QtQuick
import "../Kante"

/**
 * Plasmai's own colors on top of KanteStyle (Kimai entities, charts).
 */
QtObject {
    // Customer, project or tag without a color from the tracker.
    readonly property color entityFallback: "#d2d6de"

    // Bars of charts without per-entity colors (time by hour).
    readonly property color chart: KanteStyle.active ? KanteStyle.infoColor : "#3584e4"
}
