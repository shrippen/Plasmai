import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "../../code/secret.js" as Secret
import "../../code/platform.js" as Platform
import "../../code/desktopBackend.js" as DesktopBackend
import ".."

/**
 * Chrome shared by every settings page. Display binds its controls with
 * `property alias cfg_*` (Plasma’s Apply path); other tabs inherit ConfigPage
 * which keeps dummy cfg_* vars so injection does not TypeError.
 *
 * Also initialises the Platform backend (DesktopBackend) so that KCM pages
 * — which run in a separate QML engine from the plasmoid widget — can use
 * the session layer: `session` reads and writes shared.json, tokens, the
 * catalog cache and place search. It never opens a connection or polls.
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

    /** The session layer, not opened: settings, tokens, connection test, catalog, place search. */
    readonly property Session session: Session {
        dataSource: execSource
        offlinePrefix: "config-"
    }

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            Secret.handleData(execSource, sourceName, data)
        }
    }

    Component.onDestruction: Secret.cancelAll(execSource)

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
        // can use the session layer without crashing.
        Platform.setBackend(DesktopBackend.create(
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/kwallet.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/idle.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/notify.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/sharedConfig.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/catalogCache.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/localStore.sh")),
            Secret.fileUrlToPath(Qt.resolvedUrl("../../code/systemCheck.sh"))
        ))
        if (inWindow && !pageReady) {
            pageReady = true
            pageEntered()
        }
    }
}
