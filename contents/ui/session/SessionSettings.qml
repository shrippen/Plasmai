import QtQml
import "../../code/platform.js" as Platform

/**
 * The shared.json keys the clients read, under their shared.json names.
 * apply(shared) takes what shared.json has (typed like the defaults below);
 * set(patch) changes values here and writes the patch to shared.json.
 * Widget: plasmoid.configuration stays synced to shared.json by its host,
 * which calls connection.open() (or apply()) after a change.
 */
QtObject {
    id: settings

    property QtObject session: null

    property int refreshInterval: 30
    property int recentCount: 10
    property bool confirmBeforeStop: false
    property bool confirmStartBeforePreviousEnd: true
    property bool popupShowWorkSummary: true
    property bool popupShowRecent: true
    property bool popupShowFavorites: true
    property bool popupShowContinue: true
    property bool popupShowNewActivity: true
    property bool popupShowSparkline: true
    property bool showSparklineArcs: true
    property bool showTrips: true
    property int visualStyle: 0
    property string pinnedActivities: ""
    property string workDayBegin: "09:00"
    property string workDayEnd: "17:00"
    property real latitude: 0
    property real longitude: 0
    property string locationName: ""
    property bool idleStopEnabled: false
    property int idleStopMinutes: 10
    property bool notifyOnStart: true
    property bool notifyOnStop: true
    property bool notifyOnIdleStop: true
    property bool notifyForgotToStart: false
    property string lastUsedProjectId: ""
    property string lastUsedActivityId: ""
    property string lastUsedProjectName: ""
    property string lastUsedActivityName: ""
    /** Per-profile Kimai plugin probes (a data map, see mergeMaps). */
    property string pluginProbesJson: ""

    readonly property var keys: [
        "refreshInterval", "recentCount", "confirmBeforeStop", "confirmStartBeforePreviousEnd",
        "popupShowWorkSummary", "popupShowRecent", "popupShowFavorites", "popupShowContinue",
        "popupShowNewActivity", "popupShowSparkline", "showSparklineArcs", "showTrips", "visualStyle",
        "pinnedActivities", "workDayBegin", "workDayEnd", "latitude", "longitude", "locationName",
        "idleStopEnabled", "idleStopMinutes", "notifyOnStart", "notifyOnStop", "notifyOnIdleStop",
        "notifyForgotToStart", "lastUsedProjectId", "lastUsedActivityId", "lastUsedProjectName",
        "lastUsedActivityName", "pluginProbesJson"
    ]

    /** keys: the names that changed. */
    signal changed(var keys)

    /** Takes every known key shared.json has with the right type. */
    function apply(shared) {
        if (!shared) {
            return
        }
        const taken = []
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i]
            if (typeof shared[key] !== typeof settings[key]) {
                continue
            }
            settings[key] = shared[key]
            taken.push(key)
        }
        changed(taken)
    }

    /** Changes values here and in shared.json; resolves with what was written. */
    function set(patch) {
        for (const key in patch) {
            if (keys.indexOf(key) >= 0) {
                settings[key] = patch[key]
            }
        }
        changed(Object.keys(patch))
        return Platform.patchShared(session.dataSource, session.connection.config(), patch)
    }

    /**
     * Data maps (pluginProbesJson) merged onto shared.json key by key, so
     * entries another client wrote since they were loaded are kept (B9).
     */
    function mergeMaps(patch) {
        const bases = {}
        for (const key in patch) {
            bases[key] = settings[key]
            settings[key] = patch[key]
        }
        Platform.patchShared(session.dataSource, session.connection.config(), patch, bases).then(function(written) {
            for (const k in written) {
                if (settings[k] === patch[k] && written[k] !== patch[k]) {
                    settings[k] = written[k]
                }
            }
        }, function(err) {
            console.warn("Plasmai: could not save plugin probes:", err)
        })
    }
}
