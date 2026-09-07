/*
 *  SPDX-FileCopyrightText: 2015 Marco Martin <mart@kde.org>
 *
 *  SPDX-License-Identifier: LGPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls.Material
import org.kde.kirigami as Kirigami

Kirigami.BasicThemeDefinition {
    textColor: Material.foreground
    disabledTextColor: Qt.alpha(Material.foreground, 0.6)

    highlightColor: "#27AE60"
    highlightedTextColor: "#ffffff"
    backgroundColor: "#1e2e1e"
    alternateBackgroundColor: Qt.darker(backgroundColor, 1.05)

    hoverColor: "#3a3a3a"
    focusColor: "#27AE60"

    activeTextColor: "#27AE60"
    activeBackgroundColor: "#27AE60"
    linkColor: "#2980B9"
    linkBackgroundColor: "#2980B9"
    visitedLinkColor: "#7F8C8D"
    visitedLinkBackgroundColor: "#7F8C8D"
    negativeTextColor: "#DA4453"
    negativeBackgroundColor: "#DA4453"
    neutralTextColor: "#F67400"
    neutralBackgroundColor: "#F67400"
    positiveTextColor: "#27AE60"
    positiveBackgroundColor: "#27AE60"

    buttonTextColor: Material.foreground
    buttonBackgroundColor: Qt.darker(Material.background, 1.2)
    buttonAlternateBackgroundColor: Qt.darker(Material.background, 1.3)
    buttonHoverColor: "#3a3a3a"
    buttonFocusColor: "#27AE60"

    viewTextColor: Material.foreground
    viewBackgroundColor: Material.dialogColor
    viewAlternateBackgroundColor: Qt.darker(Material.dialogColor, 1.05)
    viewHoverColor: Material.listHighlightColor
    viewFocusColor: Material.listHighlightColor

    selectionTextColor: "#ffffff"
    selectionBackgroundColor: "#27AE60"
    selectionAlternateBackgroundColor: Qt.darker(selectionBackgroundColor, 1.05)
    selectionHoverColor: Qt.lighter(selectionBackgroundColor, 1.2)
    selectionFocusColor: selectionBackgroundColor

    tooltipTextColor: "#ffffff"
    tooltipBackgroundColor: "#3a3a3a"
    tooltipAlternateBackgroundColor: Qt.darker(tooltipBackgroundColor, 1.05)
    tooltipHoverColor: "#4a4a4a"
    tooltipFocusColor: "#27AE60"

    complementaryTextColor: "#ffffff"
    complementaryBackgroundColor: "#1a1a2e"
    complementaryAlternateBackgroundColor: Qt.lighter(complementaryBackgroundColor, 1.05)
    complementaryHoverColor: "#252540"
    complementaryFocusColor: "#27AE60"

    headerTextColor: "#ffffff"
    headerBackgroundColor: "#2d2d2d"
    headerAlternateBackgroundColor: Qt.lighter(headerBackgroundColor, 1.05)
    headerHoverColor: "#3a3a3a"
    headerFocusColor: "#27AE60"

    defaultFont: fontMetrics.font

    property list<QtObject> children: [
        TextMetrics {
            id: fontMetrics
            Material.theme: Material.Dark
        }
    ]

    onSync: object => {
        if (object && object.Kirigami && object.Kirigami.Theme) {
            object.Material.theme = Material.Dark
            object.Material.foreground = object.Kirigami.Theme.textColor
            object.Material.background = object.Kirigami.Theme.backgroundColor
            object.Material.primary = object.Kirigami.Theme.highlightColor
            object.Material.accent = object.Kirigami.Theme.highlightColor
        }
    }
}
