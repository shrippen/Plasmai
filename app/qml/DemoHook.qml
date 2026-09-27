import QtQuick
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/demoKimai.js" as DemoKimai
import "../contents/code/profiles.js" as Profiles
import "../contents/code/platform.js" as Platform

/**
 * Internal only (-DPLASMAI_DEMO, screenshots and testing): the demo Kimai behind
 * DemoKimai.DEMO_URL. Published builds do not contain this file or the demo code.
 */
Item {
    id: hook

    property var appRoot: null

    Component.onCompleted: KimaiApi.setUrlRoute(DemoKimai.ROUTE)

    // The token may have been looked up before the route existed.
    onAppRootChanged: {
        if (appRoot && appRoot.activeProfile && KimaiApi.routeToken(appRoot.activeProfile.url)) {
            appRoot.loadApiToken()
        }
    }

    /** Switch to the demo profile (made-up data in memory, nothing stored). */
    function start() {
        var app = appRoot
        Platform.loadShared(null).then(function(shared) {
            var list = Profiles.withDemoProfile(Profiles.parseProfiles(shared ? shared.profilesJson : "", shared ? shared.kimaiUrl : ""),
                                                DemoKimai.DEMO_URL, "Demo")
            return Platform.patchShared(null, app.currentConfig(), { profilesJson: Profiles.serializeProfiles(list), activeProfileId: "demo" })
        }).then(function() {
            app.loadSharedAndConnect()
        })
    }
}
