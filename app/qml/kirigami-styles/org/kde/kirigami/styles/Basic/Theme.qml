/*
 *  SPDX-FileCopyrightText: 2015 Marco Martin <mart@kde.org>
 *
 *  SPDX-License-Identifier: LGPL-2.0-or-later
 */

import QtQuick
import org.kde.kirigami as Kirigami

/**
 * Kirigami's colors under the Basic style (Windows, macOS): Breeze, light or dark as the
 * system is set. Without this Kirigami answers Breeze Light always, and on a dark system the
 * header, the lists and everything else that reads Kirigami.Theme stayed light while the
 * controls (main.cpp hands Qt the same scheme) turned dark.
 */
Kirigami.BasicThemeDefinition {
    readonly property bool dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark

    // Breeze window, view and button colors; light and dark.
    readonly property color _fg: dark ? "#eff0f1" : "#31363b"
    readonly property color _bg: dark ? "#31363b" : "#eff0f1"
    readonly property color _view: dark ? "#232629" : "#fcfcfc"
    readonly property color _accent: "#3daee9"

    textColor: _fg
    disabledTextColor: dark ? "#a1a9b1" : "#8a9195"

    highlightColor: _accent
    highlightedTextColor: "#ffffff"
    backgroundColor: _bg
    alternateBackgroundColor: dark ? "#2a2e32" : "#e3e5e7"

    hoverColor: _accent
    focusColor: _accent

    activeTextColor: "#f67400"
    activeBackgroundColor: "#f67400"
    linkColor: dark ? "#1d99f3" : "#2980b9"
    linkBackgroundColor: dark ? "#1d99f3" : "#2980b9"
    visitedLinkColor: dark ? "#9b59b6" : "#7f8c8d"
    visitedLinkBackgroundColor: dark ? "#9b59b6" : "#7f8c8d"
    negativeTextColor: dark ? "#da4453" : "#da4453"
    negativeBackgroundColor: "#da4453"
    neutralTextColor: dark ? "#f67400" : "#c9ce3b"
    neutralBackgroundColor: "#f67400"
    positiveTextColor: dark ? "#27ae60" : "#27ae60"
    positiveBackgroundColor: "#27ae60"

    buttonTextColor: _fg
    buttonBackgroundColor: _bg
    buttonAlternateBackgroundColor: dark ? "#2a2e32" : "#e3e5e7"
    buttonHoverColor: _accent
    buttonFocusColor: _accent

    viewTextColor: dark ? "#eff0f1" : "#232629"
    viewBackgroundColor: _view
    viewAlternateBackgroundColor: dark ? "#1d1f22" : "#eff0f1"
    viewHoverColor: _accent
    viewFocusColor: _accent

    selectionTextColor: "#ffffff"
    selectionBackgroundColor: _accent
    selectionAlternateBackgroundColor: Qt.darker(_accent, 1.05)
    selectionHoverColor: _accent
    selectionFocusColor: _accent

    tooltipTextColor: dark ? "#eff0f1" : "#eff0f1"
    tooltipBackgroundColor: dark ? "#31363b" : "#31363b"
    tooltipAlternateBackgroundColor: Qt.darker(tooltipBackgroundColor, 1.05)
    tooltipHoverColor: _accent
    tooltipFocusColor: _accent

    complementaryTextColor: "#eff0f1"
    complementaryBackgroundColor: "#31363b"
    complementaryAlternateBackgroundColor: "#2a2e32"
    complementaryHoverColor: _accent
    complementaryFocusColor: _accent

    // The header is the window's color: a tool bar and its buttons are one surface.
    headerTextColor: _fg
    headerBackgroundColor: _bg
    headerAlternateBackgroundColor: alternateBackgroundColor
    headerHoverColor: _accent
    headerFocusColor: _accent

    defaultFont: fontMetrics.font

    property list<QtObject> children: [
        TextMetrics {
            id: fontMetrics
        }
    ]
}
