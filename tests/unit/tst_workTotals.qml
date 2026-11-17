import QtQuick
import QtTest
import "../../contents/code/workTotals.js" as WorkTotals

/**
 * workTotals.js: today / week seconds, targets and absence credit, shared by
 * the Plasmoid and the app. A fake tracker answers at once; stamps are local
 * times, so the days hold in every time zone.
 */
TestCase {
    name: "WorkTotals"

    // Wednesday noon; the week starts Monday 2026-09-28.
    readonly property var now: new Date(2026, 8, 30, 12, 0)

    function at(day, h, m) {
        return new Date(2026, 8, day, h, m).toISOString()
    }

    // Kimai's work preferences: one hour on Wednesdays (now), nothing else.
    readonly property var wednesdayPrefs: ({ work_contract_type: "day", work_wednesday: "3600" })

    function tracker(user, entries) {
        return {
            preferenceMap: function(u) { return u.prefs },
            fetchCurrentUser: function(url, token, cb) {
                cb(user ? { ok: true, data: user } : { ok: false, error: {} })
            },
            fetchTimesheetsRange: function(url, token, begin, end, cb) {
                cb(entries ? { ok: true, data: entries } : { ok: false, error: {} })
            }
        }
    }

    // A night shoot from yesterday counts its part after midnight today; the
    // running entry counts until now.
    function test_summarizeTodayAndWeek() {
        var night = { begin: at(29, 22, 0), end: at(30, 2, 0) }
        var running = { begin: at(30, 10, 0), end: null }
        var t = WorkTotals.summarize({
            now: now, nowMs: now.getTime(), tracker: tracker(null, null),
            user: { prefs: { work_contract_type: "week", hours_per_week: 40 * 3600 } }, holidayBundle: false,
            adjustments: null, weekEntries: [night, running]
        })
        verify(t.entriesLoaded)
        compare(t.todaySeconds, 4 * 3600)
        compare(t.weekSeconds, 6 * 3600)
        compare(t.todayEntries.length, 2)
        verify(t.hasWorkContract)
        compare(t.todayTargetSeconds, 8 * 3600)
        compare(t.weekEffectiveTargetSeconds, 40 * 3600)
        compare(t.weekAbsenceCreditSeconds, 0)
    }

    // No user answer: no contract, no targets; entries still counted.
    function test_summarizeWithoutUser() {
        var t = WorkTotals.summarize({
            now: now, nowMs: now.getTime(), tracker: tracker(null, null), user: null,
            holidayBundle: true, adjustments: null,
            weekEntries: [{ begin: at(28, 9, 0), end: at(28, 10, 30) }]
        })
        verify(!t.hasWorkContract)
        compare(t.weekTargetSeconds, 0)
        compare(t.weekSeconds, 90 * 60)
        compare(t.todaySeconds, 0)
    }

    // load(): one callback with everything; a failed entry fetch keeps entriesLoaded false.
    function test_load() {
        var calls = 0
        var got = null
        var entries = [{ begin: at(30, 8, 0), end: at(30, 9, 0) }]
        WorkTotals.load({ tracker: tracker({ prefs: wednesdayPrefs }, entries), url: "u", token: "t",
                          holidayBundle: false, nowMs: now.getTime() }, now, function(t) { calls++; got = t })
        compare(calls, 1)
        compare(got.todaySeconds, 3600)
        compare(got.todayTargetSeconds, 3600)

        WorkTotals.load({ tracker: tracker({ prefs: wednesdayPrefs }, null), url: "u", token: "t",
                          holidayBundle: false, nowMs: now.getTime() }, now, function(t) { got = t })
        verify(!got.entriesLoaded)
        compare(got.todayTargetSeconds, 3600)
    }

    // With a memo the user (work preferences) is fetched once per MEMO_MS: the poll
    // reloads the week's entries only. Another week or an older memo fetches again.
    function test_loadMemo() {
        var users = 0
        var t = tracker({ prefs: wednesdayPrefs }, [])
        var fetchUser = t.fetchCurrentUser
        t.fetchCurrentUser = function(url, token, cb) { users++; fetchUser(url, token, cb) }
        var memo = {}
        var got = null
        function load(ms, when) {
            WorkTotals.load({ tracker: t, url: "u", token: "t", holidayBundle: false, nowMs: ms, memo: memo },
                            when, function(r) { got = r })
        }
        load(now.getTime(), now)
        load(now.getTime() + 60000, now)
        compare(users, 1)
        compare(got.todayTargetSeconds, 3600)
        load(now.getTime() + WorkTotals.MEMO_MS + 1, now)
        compare(users, 2)
        var nextWeek = new Date(2026, 9, 7, 12, 0)
        load(nextWeek.getTime(), nextWeek)
        compare(users, 3)
    }

    // The holiday plugin is asked through the tracker, and only with a contract and the bundle.
    function test_loadAdjustmentsThroughTracker() {
        var asked = []
        var t = tracker({ prefs: wednesdayPrefs }, [])
        t.fetchContractAdjustments = function(url, token, when, prefs, cb) {
            asked.push(prefs.work_contract_type)
            cb({ ok: true, data: { absences: [], publicHolidays: [{ date: "2026-09-30", name: "H" }] } })
        }
        var got = null
        WorkTotals.load({ tracker: t, url: "u", token: "t", holidayBundle: true, nowMs: now.getTime() },
                        now, function(r) { got = r })
        compare(asked, ["day"])
        compare(got.publicHolidays.length, 1)

        asked = []
        WorkTotals.load({ tracker: t, url: "u", token: "t", holidayBundle: false, nowMs: now.getTime() },
                        now, function(r) { got = r })
        compare(asked, [])
    }
}
