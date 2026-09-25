Qt.include("../../contents/code/colorDistinct.js")

/**
 * Runs the color-distinction algorithm (rebuild + maintenanceGroups) off the
 * GUI thread. Loaded via Qt.include() rather than `.import ... as ColorDistinct`
 * — WorkerScript on this Qt version hangs (never delivers onMessage, no crash,
 * no error) when a source script `.import`s an external `.pragma library`
 * file; Qt.include() merges the script into this file's own scope instead, so
 * every colorDistinct.js function below is called unprefixed. WorkerScript
 * loads this file into its own QQmlEngine, so this file's copy of that module
 * state is separate from the one the main thread's CustomerColorDot/
 * ColorLabelRow bindings read — the computed maps are shipped back via
 * sendMessage() and applied on the main thread through ColorDistinct.importMaps()
 * (see main.qml).
 *
 * Expects a message shaped like:
 * {
 *   customers, projects, activities: [...],
 *   themePalette: ["#rrggbb", ...],
 *   enabled: bool, similarityPercent: int, force: bool,
 *   requestId: number  // echoed back so a stale reply can be ignored
 * }
 */
WorkerScript.onMessage = function(msg) {
    var customers = msg.customers || []
    var projects = msg.projects || []
    var activities = msg.activities || []

    setThemePalette(msg.themePalette || [])
    configure(!!msg.enabled, msg.similarityPercent || 22)
    rebuild(customers, projects, activities, !!msg.force)

    var state = exportMaps()
    var storeGroups = !!msg.enabled && (customers.length || projects.length || activities.length)

    WorkerScript.sendMessage({
        requestId: msg.requestId,
        maps: state.maps,
        originals: state.originals,
        effectiveSimilarity: state.effectiveSimilarity,
        customerGroups: storeGroups ? maintenanceGroups("customer", customers) : [],
        projectGroups: storeGroups ? maintenanceGroups("project", projects) : [],
        activityGroups: storeGroups ? maintenanceGroups("activity", activities) : []
    })
}
