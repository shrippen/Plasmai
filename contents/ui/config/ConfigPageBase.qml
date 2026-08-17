import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

/**
 * Chrome shared by every settings page. Display binds its controls with
 * `property alias cfg_*` (Plasma’s Apply path); other tabs inherit ConfigPage
 * which keeps dummy cfg_* vars so injection does not TypeError.
 */
Kirigami.Page {
    id: root

    padding: 0
    globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None

    readonly property bool inWindow: Window.window !== null
    property bool pageReady: false
    /** Plasma enables Apply when cfg_* differ or this is true. */
    property bool unsavedChanges: false

    signal pageEntered
    /** Emit when the user edits a control (AppletConfiguration listens). */
    signal configurationChanged

    onInWindowChanged: {
        if (inWindow && !pageReady) {
            pageReady = true
            pageEntered()
        }
    }

    Component.onCompleted: {
        if (inWindow && !pageReady) {
            pageReady = true
            pageEntered()
        }
    }
}
