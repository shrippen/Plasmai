import QtQuick
import QtTest
import "../../contents/code/filmDaySync.js" as Sync

/**
 * filmDaySync.js asks the tracker of its ctx for every plugin request (probe,
 * day, summary, engagements, status), never Kimai's module itself: the offline
 * layer and a test can stand in. A recording tracker answers at once.
 */
TestCase {
    name: "FilmDaySyncTracker"

    function ping(features) {
        return { installed: true, apiVersions: ["v1"], permissions: { view: true, manage: false }, features: features }
    }

    function serverDay() {
        return { date: "2026-09-14", engagementId: 1, breakMinutes: null, catering: false,
                 category: null, note: null, dayType: "workday", productionDay: null,
                 extraPayCents: 0, shootingDayNumber: null, defaultBreakMinutes: 45,
                 effectiveCategory: "workday" }
    }

    function ctx(features, tracker) {
        return { url: "http://k", token: "t", profileKey: Sync.profileKey("p1", "http://k"),
                 mode: "server", ping: ping(features), memo: {}, nowMs: 5000, tracker: tracker }
    }

    function recordingTracker(log) {
        function rec(name, answer) {
            return function() {
                var args = Array.prototype.slice.call(arguments)
                log.push(name)
                args[args.length - 1](answer)
            }
        }
        return {
            detectDrehzettel: rec("detect", { state: "present", data: ping(["daySummary", "engagements"]), cacheEntry: null }),
            fetchFilmDay: rec("filmDay", { ok: true, data: serverDay() }),
            fetchDaySummary: rec("summary", { ok: true, data: { payCents: 5 } }),
            fetchDrehzettelEngagements: rec("engagements", { ok: true, data: [{ projectId: 1, rulesetName: "R" }] }),
            fetchEngagementStatus: rec("status", { ok: true, data: { active: true, rulesetName: "S" } }),
            putFilmDay: rec("put", { ok: true, data: null })
        }
    }

    function test_probeThroughTracker() {
        var log = []
        var got = null
        Sync.resolveMode("http://k", "t", "p1", {}, { tracker: recordingTracker(log) }, function(r) { got = r })
        compare(log, ["detect"])
        compare(got.mode, "server")
    }

    function test_loadDayThroughTracker() {
        var log = []
        var got = null
        var c = ctx(["daySummary", "engagements"], recordingTracker(log))
        Sync.loadDay(c, 1, "2026-09-14", function(r) { got = r })
        compare(log.sort(), ["engagements", "filmDay", "summary"])
        compare(got.rulesetName, "R")
        compare(got.summary.payCents, 5)
    }

    function test_rulesetStatusThroughTracker() {
        var log = []
        var got = null
        var c = ctx(["errorCodes"], recordingTracker(log))
        Sync.loadDay(c, 1, "2026-09-14", function(r) { got = r })
        compare(log.sort(), ["filmDay", "status"])
        compare(got.rulesetName, "S")
    }
}
