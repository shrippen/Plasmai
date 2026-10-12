import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/demoKimai.js" as DemoKimai
import "../../contents/code/platform.js" as Platform
import "../../contents/code/profiles.js" as Profiles
import "../../contents/code/sharedConfig.js" as SharedConfig

/**
 * The parts of Session.qml against the demo Kimai (in memory, no network):
 * connection, settings, catalog, timer, favorites, entries, totals, sync,
 * plugins, reminders and setup. The platform backend is an in-memory
 * shared.json, token and file store.
 */
TestCase {
    name: "SessionParts"

    property var files: ({})
    property var tokens: ({})
    property var shared: null
    property var notes: []
    property int idleMs: 0

    function backend() {
        return {
            loadSharedConfig: function(_ds, cb) { cb(shared ? JSON.parse(JSON.stringify(shared)) : null) },
            saveSharedConfig: function(_ds, obj, cb) { shared = obj; if (cb) { cb(true) } },
            loadToken: function(_ds, id, cb) { cb(tokens[id] || "", null) },
            saveToken: function(_ds, id, token, cb) { tokens[id] = token; cb(true, null) },
            clearToken: function(_ds, id, cb) { delete tokens[id]; cb(true, null) },
            loadLocal: function(_ds, name, cb) { cb(files[name] || null) },
            saveLocal: function(_ds, name, payload, cb) { files[name] = payload; cb(true, null) },
            runIdle: function(_ds, cb) { cb(idleMs, null) },
            notify: function(_ds, summary, body, cb) { notes.push(summary); cb() }
        }
    }

    function demoShared() {
        const list = Profiles.withDemoProfile(Profiles.defaultProfiles(), DemoKimai.DEMO_URL, "Demo")
        const s = { profilesJson: Profiles.serializeProfiles(list), activeProfileId: "demo", recentCount: 5 }
        s[SharedConfig.VERSION_KEY] = SharedConfig.SETTINGS_VERSION
        return s
    }

    Component {
        id: sessionComponent
        Ui.Session { setupMode: Ui.Session.Setup.Run }
    }

    Component {
        id: signalSpy
        SignalSpy { }
    }

    function initTestCase() {
        KimaiApi.setUrlRoute(DemoKimai.ROUTE)
    }

    function cleanupTestCase() {
        KimaiApi.setUrlRoute(null)
    }

    function init() {
        DemoKimai.reset()
        files = {}
        tokens = {}
        notes = []
        idleMs = 0
    }

    function spy(target, signalName) {
        return createTemporaryObject(signalSpy, this, { target: target, signalName: signalName })
    }

    function openDemo() {
        shared = demoShared()
        Platform.setBackend(backend())
        const s = createTemporaryObject(sessionComponent, this)
        s.open()
        tryCompare(s.connection, "state", s.connection.online)
        tryVerify(function() { return s.recent.list.length > 0 && s.catalog.projects.length > 0 })
        tryCompare(s, "busy", false)
        return s
    }

    // ── connection, settings ──

    function test_openReadsSettingsAndProfile() {
        const s = openDemo()
        compare(s.connection.profile.id, "demo")
        verify(s.connection.configured)
        compare(s.settings.recentCount, 5)
        compare(s.connection.config().activeProfileId, "demo")
        verify(s.connection.capabilities.tags)
    }

    function test_runModeResetsOldSettings() {
        shared = { kimaiUrl: "https://old.example", popupShowRecent: false }
        tokens = { "default": "secret" }
        Platform.setBackend(backend())
        const s = createTemporaryObject(sessionComponent, this)
        s.open()
        tryCompare(s.connection, "tokenLoaded", true)
        compare(s.connection.state, s.connection.unconfigured)
        verify(!tokens["default"])
        compare(shared[SharedConfig.VERSION_KEY], SharedConfig.SETTINGS_VERSION)
        verify(s.setup.showWizard)
    }

    function test_settingsSetWritesShared() {
        const s = openDemo()
        const changed = spy(s.settings, "changed")
        s.settings.set({ popupShowRecent: false })
        compare(s.settings.popupShowRecent, false)
        compare(changed.count, 1)
        tryVerify(function() { return shared.popupShowRecent === false })
        compare(shared.activeProfileId, "demo")
    }

    function test_connectionTokenActions() {
        const s = openDemo()
        const seen = []
        s.connection.saveToken("other", "t1").then(function() {
            return s.connection.hasToken("other")
        }).then(function(has) {
            seen.push(has)
            return s.connection.clearToken("other")
        }).then(function() {
            return s.connection.hasToken("other")
        }).then(function(has) {
            seen.push(has)
        })
        tryVerify(function() { return seen.length === 2 })
        compare(seen, [true, false])
    }

    function test_connectionTestSteps() {
        const s = openDemo()
        let steps = []
        s.connection.test({ id: "nothing", url: DemoKimai.DEMO_URL, provider: "kimai" }, {
            noToken: function() { steps.push("noToken") },
            testing: function() { steps.push("testing") },
            done: function() { steps.push("done") },
            failed: function() { steps.push("failed") }
        })
        tryVerify(function() { return steps.length > 0 })
        compare(steps[0], "noToken")
    }

    // ── catalog, favorites ──

    function test_catalogPickerAndActivities() {
        const s = openDemo()
        verify(s.catalog.projectPickerModel.length > 0)
        const project = s.catalog.projects[0]
        compare(s.catalog.projectById(String(project.id)).id, project.id)
        let model = null
        s.catalog.loadActivities(project.id, function(m) { model = m })
        tryVerify(function() { return model !== null })
        verify(model.length > 0)
        verify(!!s.catalog.activitiesByProject[String(project.id)])
    }

    function test_favoritesToggle() {
        const s = openDemo()
        const pid = String(s.catalog.projects[0].id)
        const aid = String(s.catalog.activities[0].id)
        verify(!s.favorites.isPinned(pid, aid))
        s.favorites.toggle(pid, aid)
        verify(s.favorites.isPinned(pid, aid))
        compare(s.favorites.pinned.length, 1)
        s.favorites.toggle(pid, aid)
        compare(s.favorites.pinned.length, 0)
    }

    // ── timer ──

    function test_restartDecisions() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        const same = { project: KimaiApi.projectId(s.timer.active), activity: KimaiApi.activityId(s.timer.active) }
        compare(s.timer.requestRestart(same), Ui.Session.Restart.Hint)
        const other = s.recent.list.filter(function(r) {
            return String(KimaiApi.activityId(r)) !== String(same.activity)
        })[0]
        compare(s.timer.requestRestart(other), Ui.Session.Restart.Confirm)
        compare(s.timer.start(KimaiApi.projectId(other), KimaiApi.activityId(other), "", "", ""), Ui.Session.Restart.Confirm)

        s.timer.stop()
        tryCompare(s.timer, "tracking", false)
        tryCompare(s, "busy", false)
        compare(s.timer.requestRestart(other), Ui.Session.Restart.Continued)
        tryCompare(s.timer, "tracking", true)
    }

    function test_startNotifiesAndRemembersLastUsed() {
        const s = openDemo()
        s.timer.stop()
        tryCompare(s.timer, "tracking", false)
        tryCompare(s, "busy", false)
        const started = spy(s, "started")
        const began = spy(s, "trackingBegan")
        const first = s.recent.list[0]
        s.timer.start(KimaiApi.projectId(first), KimaiApi.activityId(first), "P", "A", "")
        tryCompare(s.timer, "tracking", true)
        compare(started.count, 1)
        compare(started.signalArguments[0][1], Ui.Session.Origin.Start)
        compare(started.signalArguments[0][2].project, "P")
        compare(began.count, 1)
        compare(s.settings.lastUsedProjectId, String(KimaiApi.projectId(first)))
        verify(s.timer.hasLastUsed)
    }

    function test_descriptionSavedAfterPause() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        const saved = spy(s.timer, "descriptionSaved")
        s.timer.saveDescription("Typed here")
        compare(s.timer.draft, "Typed here")
        tryCompare(saved, "count", 1, 3000)
        compare(s.timer.description, "Typed here")
        // A refresh keeps what was saved.
        s.refresh()
        tryCompare(s, "busy", false)
        compare(s.timer.description, "Typed here")
    }

    function test_patchActiveMovesBegin() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        const begin = new Date(Date.now() - 3 * 3600 * 1000)
        begin.setSeconds(0, 0)
        s.timer.patchActive({ begin: KimaiApi.localDateTimeString(begin) })
        tryVerify(function() { return Math.abs(s.timer.elapsedSeconds - 3 * 3600) < 120 })
    }

    // ── entries, totals ──

    function test_writeSplitAndRemove() {
        const s = openDemo()
        const first = s.recent.list[0]
        const day = new Date()
        day.setDate(day.getDate() - 2)
        day.setHours(9, 0, 0, 0)
        const end = new Date(day.getTime() + 2 * 3600 * 1000)
        let answer = null
        s.entries.write(null, { project: KimaiApi.projectId(first), activity: KimaiApi.activityId(first),
                                begin: KimaiApi.localDateTimeString(day), end: KimaiApi.localDateTimeString(end),
                                description: "Two hours" }, function(r) { answer = r })
        tryVerify(function() { return answer !== null })
        verify(answer.ok)
        const created = answer.data

        const failed = spy(s, "failed")
        s.entries.split(created, new Date(end.getTime() + 3600 * 1000))
        compare(failed.count, 1)
        compare(failed.signalArguments[0][0], Ui.Session.Action.SplitRange)

        let range = null
        s.entries.split(created, new Date(day.getTime() + 3600 * 1000))
        tryCompare(s, "busy", false)
        s.entries.fetchRange(day, end, function(r) { range = r })
        tryVerify(function() { return range !== null })
        const halves = range.data.filter(function(ts) { return ts.description === "Two hours" })
        compare(halves.length, 2)
        verify(typeof halves[0].project === "object")

        s.entries.remove(halves[0])
        tryCompare(s, "busy", false)
        range = null
        s.entries.fetchRange(day, end, function(r) { range = r })
        tryVerify(function() { return range !== null })
        compare(range.data.filter(function(ts) { return ts.description === "Two hours" }).length, 1)
    }

    function test_doneCallbacks() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        const first = s.recent.list[0]
        const day = new Date()
        day.setDate(day.getDate() - 3)
        day.setHours(9, 0, 0, 0)
        const end = new Date(day.getTime() + 2 * 3600 * 1000)
        let created = null
        s.entries.write(null, { project: KimaiApi.projectId(first), activity: KimaiApi.activityId(first),
                                begin: KimaiApi.localDateTimeString(day), end: KimaiApi.localDateTimeString(end),
                                description: "Done test" }, function(r) { created = r.data })
        tryVerify(function() { return created !== null })

        const done = []
        s.entries.split(created, new Date(day.getTime() + 3600 * 1000), function() { done.push("split") })
        tryVerify(function() { return done.length === 1 })
        tryCompare(s, "busy", false)
        s.entries.remove(created, function() { done.push("remove") })
        tryVerify(function() { return done.length === 2 })
        tryCompare(s, "busy", false)
        s.timer.patchActive({ description: "patched" }, function() { done.push("patch") })
        tryVerify(function() { return done.length === 3 })
        compare(done, ["split", "remove", "patch"])
    }

    // ── loading, catalog refill, draft (the widget's needs) ──

    function test_loadedFlags() {
        const s = openDemo()
        tryVerify(function() { return s.timer.loaded && s.recent.loaded && s.catalog.loaded })
        compare(s.connection.lastError, null)
    }

    function test_catalogRefillsNames() {
        const s = openDemo()
        tryVerify(function() { return s.catalog.loaded })
        // Entries that came before the catalog: ids only.
        s.recent.list = s.recent.list.map(function(ts) {
            return Object.assign({}, ts, { project: KimaiApi.projectId(ts), activity: KimaiApi.activityId(ts) })
        })
        verify(typeof s.recent.list[0].project !== "object")
        const updated = spy(s.catalog, "updated")
        s.catalog.invalidate()
        s.catalog.refresh()
        tryCompare(updated, "count", 1)
        verify(typeof s.recent.list[0].project === "object")
    }

    function test_draftWaitsForFlush() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        const saved = spy(s.timer, "descriptionSaved")
        s.timer.setDraft("Typed, not saved")
        wait(1200)
        compare(saved.count, 0)
        verify(s.timer.description !== "Typed, not saved")
        s.timer.flushDescription()
        tryCompare(saved, "count", 1)
        compare(s.timer.description, "Typed, not saved")
    }

    function test_createEntityAndTags() {
        const s = openDemo()
        const before = s.catalog.customers.length
        let result = null
        s.entries.createEntity("customer", { name: "Session test" }, function(r) { result = r })
        tryVerify(function() { return result !== null })
        verify(result.ok)
        tryVerify(function() { return s.catalog.customers.length === before + 1 })

        let tags = null
        s.entries.loadTags("", function(r) { tags = r })
        tryVerify(function() { return tags !== null })
        verify(tags.ok)
        verify(s.entries.canCreate)
    }

    function test_totalsGrowWithTheTimer() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking && s.totals.todaySeconds > 0 })
        const live = s.totals.todayLiveSeconds
        s.timer.elapsedSeconds += 60
        compare(s.totals.todayLiveSeconds, live + 60)
        verify(s.totals.hasWorkContract)
        verify(s.totals.weekEffectiveTargetSeconds > 0)
    }

    // ── sync, plugins ──

    function test_syncStartsEmptyAndOnline() {
        const s = openDemo()
        verify(!s.sync.offline)
        compare(s.sync.unsynced, 0)
        compare(s.sync.ops.length, 0)
        verify(!s.sync.isUnsynced(s.recent.list[0].id))
    }

    function test_pluginsProbed() {
        const s = openDemo()
        tryVerify(function() { return s.filmDay.available })
        tryVerify(function() { return s.trips.available && s.trips.canEdit })
        tryVerify(function() { return s.settings.pluginProbesJson.length > 0 })
        tryVerify(function() { return !!s.trips.meta })
        let trips = null
        s.trips.fetch({ year: new Date().getFullYear() }, function(r) { trips = r })
        tryVerify(function() { return trips !== null })
        verify(trips.ok)
    }

    function test_filmDayOpensToday() {
        const s = openDemo()
        tryVerify(function() { return s.filmDay.available })
        let opened = null
        s.filmDay.openDay(new Date(), null, function(r, entries) { opened = r })
        tryVerify(function() { return opened !== null })
        verify(!!opened.day)
    }

    // ── reminders, setup ──

    function test_idleDiscardAndContinue() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        s.reminders.notificationsAvailable = true
        const discarded = spy(s.reminders, "idleDiscarded")
        s.reminders.promptIdle(20 * 60 * 1000)
        verify(s.reminders.idlePending)
        verify(!!s.reminders.snapshot)
        s.reminders.discard(Ui.Session.AfterIdle.Continue)
        verify(!s.reminders.idlePending)
        tryCompare(discarded, "count", 1)
        tryVerify(function() { return s.timer.tracking && s.timer.elapsedSeconds < 60 })
    }

    function test_idleKeep() {
        const s = openDemo()
        tryVerify(function() { return s.timer.tracking })
        s.reminders.promptIdle(20 * 60 * 1000)
        s.reminders.keep()
        verify(s.reminders.ignoreUntilActive)
        verify(!s.reminders.idlePending)
        verify(s.timer.tracking)
    }

    function test_setupAppliesConnection() {
        const s = openDemo()
        compare(s.setup.providerName("kimai"), "Kimai")
        verify(s.setup.listProviders().length >= 4)
        s.setup.applyConnection({ activeProfileId: "demo" })
        verify(s.setup.awaitingDay)
        verify(s.setup.showWizard)
        s.setup.finish({ workDayBegin: "07:30" })
        verify(!s.setup.awaitingDay)
        compare(s.settings.workDayBegin, "07:30")
        tryVerify(function() { return shared.workDayBegin === "07:30" })
    }
}
