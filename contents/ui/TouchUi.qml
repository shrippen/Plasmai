pragma Singleton
import QtQuick
import org.kde.kirigami as Kirigami

/**
 * Central touch / tablet sizing for Plasmai.
 * preference: 0 = auto (follow Plasma tablet mode), 1 = on, 2 = off
 * Bind preference from plasmoid.configuration.touchMode in main.qml.
 */
QtObject {
    id: root

    property int preference: 0

    readonly property bool systemSuggestsTouch: Kirigami.Settings.tabletMode

    readonly property bool active: preference === 1
                                   || (preference === 0 && systemSuggestsTouch)

    /**
     * Multiplier for layout gaps (favorites grid, etc.).
     * Reserved for overall denser/looser spacing without changing each control size.
     */
    readonly property real spacingScale: active ? 1.25 : 1.0

    readonly property int smallSpacing: Math.round(Kirigami.Units.smallSpacing * spacingScale)

    readonly property int iconSize: active
                                    ? Kirigami.Units.iconSizes.medium
                                    : Kirigami.Units.iconSizes.small

    readonly property int compactIconSize: active
                                           ? Kirigami.Units.iconSizes.large
                                           : Kirigami.Units.iconSizes.medium

    readonly property int rowMinHeight: active
                                        ? Math.round(Kirigami.Units.gridUnit * 2.75)
                                        : 0

    readonly property int controlMinHeight: active
                                            ? Math.round(Kirigami.Units.gridUnit * 2.5)
                                            : 0

    /** Minimum action-button height; only applied when touch mode is active. */
    readonly property int buttonMinHeight: active
                                           ? Math.round(Kirigami.Units.gridUnit * 2.5)
                                           : 0

    readonly property int pickerEntryHeight: active
                                             ? Math.round(Kirigami.Units.gridUnit * 2.25)
                                             : (Kirigami.Units.gridUnit + Kirigami.Units.smallSpacing)

    readonly property int pickerSectionHeight: active
                                               ? Math.round(Kirigami.Units.gridUnit * 1.6)
                                               : (Math.max(Kirigami.Units.iconSizes.small * 0.85, Kirigami.Units.gridUnit)
                                                  + Kirigami.Units.smallSpacing)

    readonly property int pickerMinVisibleEntries: active ? 12 : 15
    readonly property int pickerDirectionEntries: active ? 8 : 10

    readonly property int flyoutPreferredHeightGu: active ? 32 : 28
    readonly property int flyoutMinHeightGu: active ? 16 : 12
    readonly property int flyoutPreferredWidthGu: active ? 24 : 22

    readonly property int favoriteCellGu: active ? 8 : 7

    readonly property real calendarCellGu: active ? 2.2 : 1.6
    readonly property int tumblerWidthGu: active ? 4 : 3
    readonly property int tumblerHeightGu: active ? 8 : 6

    readonly property int chartHitSlop: active
                                        ? Math.round(Kirigami.Units.smallSpacing * 2)
                                        : 0

    readonly property int listRowPadding: active
                                          ? Kirigami.Units.smallSpacing * 2
                                          : Kirigami.Units.smallSpacing
}
