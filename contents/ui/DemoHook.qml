import QtQuick
import "../code/kimaiApi.js" as KimaiApi
import "../code/demoKimai.js" as DemoKimai

/**
 * Internal only (screenshots, testing): the demo Kimai behind DemoKimai.DEMO_URL and the
 * screenshot runner. scripts/package.sh leaves this file, the demo code and the Loader in
 * main.qml out of the .plasmoid, so published widgets have no demo.
 */
Item {
    id: hook

    property var plasmoidRoot: null
    property var execSource: null

    Component.onCompleted: KimaiApi.setUrlRoute(DemoKimai.ROUTE)

    // The Loader hands the root over after creation; the token may have been looked up
    // before the route existed.
    onPlasmoidRootChanged: {
        if (plasmoidRoot && KimaiApi.routeToken(plasmoidRoot.kimaiUrl)) {
            plasmoidRoot.reloadCredentials()
        }
    }

    // The runner reads its plan at once, so it starts after the Loader has handed both over.
    Loader {
        active: hook.plasmoidRoot !== null && hook.execSource !== null
        sourceComponent: Component {
            ScreenshotRunner {
                plasmoidRoot: hook.plasmoidRoot
                execSource: hook.execSource
            }
        }
    }
}
