import QtQuick
import QtTest

/**
 * The app's Kirigami themes (Material: Android; Basic: Windows, macOS) give a small
 * font that is smaller than the default one. Without it Kirigami takes the platform's
 * smallest readable font, which was larger than the body text (12 pt against 9 pt) and,
 * on Android, came with "QFont::setPointSize: Point size <= 0".
 */
TestCase {
    name: "AppThemeFonts"

    function test_smallFont_data() {
        return [
            { tag: "Material", path: "../../app/qml/kirigami-styles/org/kde/kirigami/styles/Material/Theme.qml" },
            { tag: "Basic", path: "../../app/qml/kirigami-styles/org/kde/kirigami/styles/Basic/Theme.qml" }
        ]
    }

    function test_smallFont(data) {
        var c = Qt.createComponent(Qt.resolvedUrl(data.path))
        tryCompare(c, "status", Component.Ready)
        var theme = c.createObject(null)
        verify(theme)
        verify(theme.defaultFont.pointSize > 0, "default " + theme.defaultFont.pointSize)
        verify(theme.smallFont.pointSize > 0, "small " + theme.smallFont.pointSize)
        verify(theme.smallFont.pointSize < theme.defaultFont.pointSize,
               "small " + theme.smallFont.pointSize + " default " + theme.defaultFont.pointSize)
        compare(theme.smallFont.family, theme.defaultFont.family)
        theme.destroy()
    }
}
