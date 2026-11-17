import QtQml
import "../../code/platform.js" as Platform
import "../../code/sharedConfig.js" as SharedConfig

/**
 * The shared.json keys the clients read, under their shared.json names.
 * apply(shared) takes what shared.json has (typed like the defaults);
 * set(patch) changes values here and writes the patch to shared.json.
 * Widget: plasmoid.configuration stays synced to shared.json by its host,
 * which calls connection.open() (or apply()) after a change.
 */
QtObject {
    id: settings

    property QtObject session: null

    property int refreshInterval: SharedConfig.DEFAULTS.refreshInterval
    property int recentCount: SharedConfig.DEFAULTS.recentCount
    property bool confirmBeforeStop: SharedConfig.DEFAULTS.confirmBeforeStop
    property bool confirmStartBeforePreviousEnd: SharedConfig.DEFAULTS.confirmStartBeforePreviousEnd
    property bool popupShowWorkSummary: SharedConfig.DEFAULTS.popupShowWorkSummary
    property bool popupShowRecent: SharedConfig.DEFAULTS.popupShowRecent
    property bool popupShowFavorites: SharedConfig.DEFAULTS.popupShowFavorites
    property bool popupShowContinue: SharedConfig.DEFAULTS.popupShowContinue
    property bool popupShowNewActivity: SharedConfig.DEFAULTS.popupShowNewActivity
    property bool popupShowSparkline: SharedConfig.DEFAULTS.popupShowSparkline
    property bool showSparklineArcs: SharedConfig.DEFAULTS.showSparklineArcs
    property bool showTrips: SharedConfig.DEFAULTS.showTrips
    property int visualStyle: SharedConfig.DEFAULTS.visualStyle
    property string pinnedActivities: SharedConfig.DEFAULTS.pinnedActivities
    property string workDayBegin: SharedConfig.DEFAULTS.workDayBegin
    property string workDayEnd: SharedConfig.DEFAULTS.workDayEnd
    property real latitude: SharedConfig.DEFAULTS.latitude
    property real longitude: SharedConfig.DEFAULTS.longitude
    property string locationName: SharedConfig.DEFAULTS.locationName
    property bool idleStopEnabled: SharedConfig.DEFAULTS.idleStopEnabled
    property int idleStopMinutes: SharedConfig.DEFAULTS.idleStopMinutes
    property bool notifyOnStart: SharedConfig.DEFAULTS.notifyOnStart
    property bool notifyOnStop: SharedConfig.DEFAULTS.notifyOnStop
    property bool notifyOnIdleStop: SharedConfig.DEFAULTS.notifyOnIdleStop
    property bool notifyForgotToStart: SharedConfig.DEFAULTS.notifyForgotToStart
    property string lastUsedProjectId: SharedConfig.DEFAULTS.lastUsedProjectId
    property string lastUsedActivityId: SharedConfig.DEFAULTS.lastUsedActivityId
    property string lastUsedProjectName: SharedConfig.DEFAULTS.lastUsedProjectName
    property string lastUsedActivityName: SharedConfig.DEFAULTS.lastUsedActivityName
    /** Per-profile Kimai plugin probes (a data map, see mergeMaps). */
    property string pluginProbesJson: SharedConfig.DEFAULTS.pluginProbesJson

    readonly property var keys: SharedConfig.SESSION_KEYS

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

    /**
     * Changes values here and in shared.json; resolves with what was written. base: the
     * connection keys used when shared.json lacks them (settings dialog: its configuration).
     */
    function set(patch, base) {
        for (const key in patch) {
            // Typed like the defaults; anything else is only written.
            if (keys.indexOf(key) >= 0 && typeof patch[key] === typeof settings[key]) {
                settings[key] = patch[key]
            }
        }
        changed(Object.keys(patch))
        return Platform.patchShared(session.dataSource, base || session.connection.config(), patch)
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
