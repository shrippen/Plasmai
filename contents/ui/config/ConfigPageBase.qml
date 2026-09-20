import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import "../../code/secret.js" as Secret
import "../../code/platform.js" as Platform
import "../../code/desktopBackend.js" as DesktopBackend

/**
 * Chrome shared by every settings page. Display binds its controls with
 * `property alias cfg_*` (Plasma’s Apply path); other tabs inherit ConfigPage
 * which keeps dummy cfg_* vars so injection does not TypeError.
 *
 * Also initialises the Platform backend (DesktopBackend) so that KCM pages
 * — which run in a separate QML engine from the plasmoid widget — can call
 * Platform.loadToken / loadShared / … without crashing on a null _backend.
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
        // The KCM (settings dialog) runs in a separate QML engine from the
        // plasmoid widget, so .pragma library singletons like Platform have
        // a fresh _backend = null.  Initialise it here so every config page
        // (including ConfigDisplay which inherits directly from ConfigPageBase)
        // can call Platform.loadToken / loadShared / … without crashing.
        Platform.setBackend(DesktopBackend.create(
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/kwallet.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/idle.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/notify.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/sharedConfig.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/catalogCache.sh"))
        ))
        if (inWindow && !pageReady) {
            pageReady = true
            pageEntered()
        }
    }
}
