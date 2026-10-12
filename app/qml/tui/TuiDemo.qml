import QtQml
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/demoKimai.js" as DemoKimai
import "../../contents/code/profiles.js" as Profiles

/**
 * Internal only (-DPLASMAI_DEMO): `--tui --demo` runs the terminal client on
 * the demo Kimai in memory. Nothing is written to shared.json. Published
 * builds lack this file.
 */
QtObject {
    function start(session) {
        KimaiApi.setUrlRoute(DemoKimai.ROUTE)
        const demo = Profiles.withDemoProfile([], DemoKimai.DEMO_URL, "Demo")[0]
        session.profiles = [demo]
        session.useProfile(demo)
    }
}
