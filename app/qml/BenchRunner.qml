import QtQuick

/**
 * Internal benchmark of the app (demo builds only, like DemoHook.qml; never shipped), the
 * counterpart of contents/ui/BenchRunner.qml for the widget. Runs when benchProbe.requested
 * (PLASMAI_BENCH=1, or --bench; on Android the intent extra applicationArguments). Lines:
 *   PLASMAI_BENCH {"name": "...", ...}   then PLASMAI_BENCH_DONE, and the app quits.
 * demo/bench-app.sh starts it on the desktop, in the Flatpak sandbox or on a phone.
 *
 *   demo profile ─▶ data shown (startup) ─▶ idle ─▶ pages ×rounds ─▶ refresh (parts) ─▶ idle
 *
 * What a step measures (as the widget's runner):
 *   sync    ms the call itself blocked (page creation, bindings)
 *   frame   ms until the window showed the result (next frame swapped)
 *   blocked ms the event loop was late in the settle time after it
 *   popupFps frames per second of the window while nothing happens
 * The start (step "startup"): phases in ms since the process started, from benchProbe.marks():
 *   main ─▶ app (window set up, QML not loaded) ─▶ loaded (main.qml built) ─▶ firstFrame ─▶ data
 * benchProbe.startupOnly (PLASMAI_BENCH=startup, --bench-startup): the start only, then quit.
 */
Item {
    id: runner

    property var appRoot: null
    property var demoHook: null
    readonly property bool active: typeof benchProbe !== "undefined" && benchProbe.requested

    readonly property int rounds: 3
    readonly property int settleMs: 1500
    readonly property int idleMs: 10000
    readonly property int msPerTick: 10
    /** main.qml's page components by name (handed over by its Loader); "main" is the timer. */
    property var components: ({})
    readonly property var order: ["manual", "main", "stats", "main", "filmday", "main", "trips", "main", "favorites", "main"]
    readonly property var refreshParts: ["timer", "recent", "catalog", "totals", "favorites"]

    property var queue: []
    property bool started: false

    // Event-loop lag probe: a 10 ms timer; every ms it fires late is a ms the GUI thread was busy.
    property double probeLast: 0
    property double lagMs: 0
    property double lagMaxMs: 0

    Timer {
        interval: 10
        repeat: true
        running: runner.active
        onTriggered: {
            const now = Date.now()
            if (runner.probeLast > 0) {
                const late = Math.max(0, now - runner.probeLast - interval)
                runner.lagMs += late
                runner.lagMaxMs = Math.max(runner.lagMaxMs, late)
            }
            runner.probeLast = now
        }
    }

    function resetLag() {
        lagMs = 0
        lagMaxMs = 0
    }

    function emit(result) {
        console.warn("PLASMAI_BENCH " + JSON.stringify(result))
    }

    /** Memory and CPU now, in the widget runner's shape (cpuTicks at 100 per second). */
    function processStats(name, extra) {
        emit(Object.assign({ name: name, rssKb: benchProbe.rssKb(),
                             cpuTicks: Math.round(benchProbe.cpuMs() / msPerTick), spawnsTotal: 0 }, extra || {}))
    }

    /** The demo profile was asked for (after main.qml's start: the platform backend is set then). */
    property bool demoStarted: false

    // Polled often: the moment the data shows is the end of the start.
    Timer {
        id: ready
        interval: 20
        repeat: true
        running: runner.active && !runner.started && runner.appRoot !== null && runner.demoHook !== null
        onTriggered: {
            const s = runner.appRoot.session
            const demoActive = s.connection.url.indexOf("demo.invalid") >= 0
            // The demo profile first, unless the app opened it itself (a warm start: an earlier
            // run left it as the active profile, DemoHook hands it its token); the steps once its
            // data is shown.
            if (!demoActive && !runner.demoStarted) {
                runner.demoStarted = true
                runner.demoHook.start()
                return
            }
            if (!demoActive || !s.connection.configured || !s.timer.loaded || !s.recent.loaded || s.totals.todayEntries.length === 0) {
                return
            }
            runner.started = true
            runner.afterFrame(function() {
                benchProbe.mark("data")
                runner.processStats("startup", { uptimeMs: benchProbe.uptimeMs(), phases: benchProbe.marks(),
                                                 demoStarted: runner.demoStarted })
                if (benchProbe.startupOnly) {
                    console.warn("PLASMAI_BENCH_DONE")
                    Qt.quit()
                    return
                }
                runner.start()
            })
        }
    }

    function afterFrame(f) {
        const win = appRoot
        let done = false
        // frameSwapped comes from the render thread: several may be queued before the disconnect.
        function swapped() {
            win.frameSwapped.disconnect(swapped)
            if (done) {
                return
            }
            done = true
            f()
        }
        win.frameSwapped.connect(swapped)
        win.requestUpdate()
    }

    function start() {
        // The poll would refresh at random points in the steps: the steps refresh themselves.
        appRoot.session.pollTimer.running = false
        const q = [{ act: "process", name: "idle-open-begin" }, { act: "idle", name: "idle-open" },
                   { act: "process", name: "idle-open-end" }]
        for (let k = 0; k < rounds; ++k) {
            for (let i = 0; i < order.length; ++i) {
                q.push({ act: "page", value: order[i], round: k })
            }
            q.push({ act: "refresh", round: k })
            for (let i = 0; i < refreshParts.length; ++i) {
                q.push({ act: "refresh", part: refreshParts[i], round: k })
            }
        }
        q.push({ act: "process", name: "idle-collapsed-begin" })
        q.push({ act: "idle", name: "idle-collapsed" })
        q.push({ act: "process", name: "idle-collapsed-end" })
        q.push({ act: "done" })
        queue = q
        next()
    }

    function next() {
        if (queue.length === 0) {
            return
        }
        const item = queue[0]
        queue = queue.slice(1)
        switch (item.act) {
        case "page":
            timed("view-" + item.value, { round: item.round }, function() { runner.openPage(item.value) })
            return
        case "refresh": {
            const s = appRoot.session
            const call = item.part ? function() { runner.refreshPart(s, item.part) } : function() { s.refresh() }
            timed(item.part ? "refresh-" + item.part : "refresh", { round: item.round }, call)
            return
        }
        case "idle":
            idle(item.name)
            return
        case "process":
            processStats(item.name)
            ticker.go(0)
            return
        case "done":
            console.warn("PLASMAI_BENCH_DONE")
            Qt.quit()
            return
        }
    }

    function openPage(name) {
        if (name === "main") {
            appRoot.pageStack.pop(appRoot.pageStack.get(0))
            return
        }
        appRoot.navigateTo(components[name])
    }

    function refreshPart(s, part) {
        if (part === "favorites") {
            s.favorites.resolve()
            return
        }
        s[part].refresh()
    }

    /** Runs `call`, then reports its blocking time, the next frame and the lag while it settles. */
    function timed(name, extra, call) {
        resetLag()
        const t0 = Date.now()
        call()
        const sync = Date.now() - t0
        const win = appRoot
        let frame = -1
        function swapped() {
            if (frame < 0) {
                frame = Date.now() - t0
            }
        }
        win.frameSwapped.connect(swapped)
        win.requestUpdate()
        ticker.go(settleMs, function() {
            win.frameSwapped.disconnect(swapped)
            emit(Object.assign({ name: name, sync: sync, frame: frame, blocked: Math.round(lagMs),
                                 blockedMax: Math.round(lagMaxMs), spawns: 0 }, extra))
        })
    }

    /** Frames per second of the window while nothing is done (named popupFps like the widget's). */
    function idle(name) {
        let frames = 0
        function onFrame() { frames++ }
        appRoot.frameSwapped.connect(onFrame)
        resetLag()
        ticker.go(idleMs, function() {
            appRoot.frameSwapped.disconnect(onFrame)
            emit({ name: name, popupFps: frames / (idleMs / 1000), panelFps: 0, blocked: Math.round(lagMs), spawns: 0 })
        })
    }

    Timer {
        id: ticker
        property var then: null
        repeat: false
        onTriggered: {
            const f = then
            then = null
            if (f) {
                f()
            }
            runner.next()
        }
        function go(ms, f) {
            then = f || null
            interval = ms
            restart()
        }
    }
}
