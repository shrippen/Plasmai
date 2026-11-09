import QtQuick
import "../code/secret.js" as Secret

/**
 * Internal benchmark of the widget, only when a plan file exists:
 *   $XDG_CONFIG_HOME/com.github.shrippen.plasmai/bench.json   { "rounds": 3 }
 * demo/bench.sh writes it next to the demo profile and reads the result lines:
 *   PLASMAI_BENCH {"name": "...", ...}   then PLASMAI_BENCH_DONE, and the viewer quits.
 *
 * What a step measures:
 *   sync    ms the call itself blocked (view creation, bindings)
 *   frame   ms until the window showed the result (next frame swapped)
 *   blocked ms the event loop was late in the settle time after it (probe below)
 *   frames  frames drawn per second while nothing happens (animations, ticks)
 *   spawns  shell processes started (every file access goes through one)
 *
 *   plan ─▶ steps: open, idle, views ×rounds, refresh, idle-collapsed ─▶ PLASMAI_BENCH lines
 */
Item {
    id: runner

    property var plasmoidRoot: null
    property var execSource: null
    property var plan: null
    property var queue: []
    readonly property bool active: plan !== null

    /** Views and how to open them (main.qml's functions). */
    readonly property var views: ({
        manual: function(r) { r.openManualEntry() },
        stats: function(r) { r.openStatsView() },
        filmday: function(r) { r.openFilmDayView() },
        edit: function(r) { r.openActiveEdit() },
        main: function(r) { r.returnToMainView() }
    })
    readonly property int settleMs: 1500
    readonly property int idleMs: 10000

    // Event-loop lag probe: a 10 ms timer; every ms it fires late is a ms the GUI thread was busy.
    property double probeLast: 0
    property double lagMs: 0
    property double lagMaxMs: 0

    Timer {
        id: probe
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

    function load() {
        const file = "\"${XDG_CONFIG_HOME:-$HOME/.config}/com.github.shrippen.plasmai/bench.json\""
        Secret._run(execSource, "cat " + file + " 2>/dev/null", function(data) {
            const parsed = Secret.parseJsonPayload(data && data.stdout)
            if (parsed) {
                runner.plan = parsed
            }
        })
    }

    function popupWindow() {
        const item = plasmoidRoot.fullRepresentationItem
        return item ? item.Window.window : null
    }

    function panelWindow() {
        return plasmoidRoot.Window.window
    }

    function start() {
        const q = [{ act: "process", name: "startup" }, { act: "open" },
                   { act: "process", name: "idle-open-begin" }, { act: "idle", name: "idle-open" },
                   { act: "process", name: "idle-open-end" }]
        const rounds = plan.rounds || 3
        const order = ["manual", "main", "stats", "main", "filmday", "main", "edit", "main"]
        for (let k = 0; k < rounds; ++k) {
            for (let i = 0; i < order.length; ++i) {
                q.push({ act: "view", value: order[i], round: k })
            }
            q.push({ act: "refresh", round: k })
        }
        q.push({ act: "collapse" })
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
        case "open":
            timed("open", { round: 0 }, function() { plasmoidRoot.expanded = true }, popupWindow)
            return
        case "collapse":
            plasmoidRoot.expanded = false
            ticker.go(settleMs)
            return
        case "view":
            timed("view-" + item.value, { round: item.round }, function() { runner.views[item.value](plasmoidRoot) },
                  popupWindow)
            return
        case "refresh":
            timed("refresh", { round: item.round }, function() { plasmoidRoot.session.refresh() }, popupWindow)
            return
        case "idle":
            idle(item.name)
            return
        case "process":
            processStats(item.name)
            return
        case "done":
            console.warn("PLASMAI_BENCH_DONE")
            Qt.quit()
            return
        }
    }

    /** Runs `call`, then reports its blocking time, the next frame and the lag while it settles. */
    function timed(name, extra, call, windowOf) {
        const spawns = Secret._job
        resetLag()
        const t0 = Date.now()
        call()
        const sync = Date.now() - t0
        const win = windowOf()
        let frame = -1
        function swapped() {
            if (frame < 0) {
                frame = Date.now() - t0
            }
        }
        if (win) {
            win.frameSwapped.connect(swapped)
            win.requestUpdate()
        }
        ticker.go(settleMs, function() {
            if (win) {
                win.frameSwapped.disconnect(swapped)
            }
            emit(Object.assign({ name: name, sync: sync, frame: frame, blocked: Math.round(lagMs),
                                 blockedMax: Math.round(lagMaxMs), spawns: Secret._job - spawns }, extra))
        })
    }

    /** Frames per second of the popup and the panel while nothing is done. */
    function idle(name) {
        const spawns = Secret._job
        const counts = { popup: 0, panel: 0 }
        const pop = popupWindow()
        const pan = panelWindow()
        function onPopup() { counts.popup++ }
        function onPanel() { counts.panel++ }
        if (pop) {
            pop.frameSwapped.connect(onPopup)
        }
        if (pan && pan !== pop) {
            pan.frameSwapped.connect(onPanel)
        }
        resetLag()
        ticker.go(idleMs, function() {
            if (pop) {
                pop.frameSwapped.disconnect(onPopup)
            }
            if (pan && pan !== pop) {
                pan.frameSwapped.disconnect(onPanel)
            }
            const s = idleMs / 1000
            emit({ name: name, popupFps: counts.popup / s, panelFps: counts.panel / s,
                   blocked: Math.round(lagMs), spawns: Secret._job - spawns })
        })
    }

    /** RSS and CPU time of the viewer: the outer shell's parent is the viewer. */
    function processStats(name) {
        Secret._run(execSource, "grep VmRSS /proc/$PPID/status; cut -d' ' -f14,15 /proc/$PPID/stat", function(data) {
            const out = String(data && data.stdout || "")
            const rss = /VmRSS:\s+(\d+)/.exec(out)
            const cpu = /^(\d+) (\d+)$/m.exec(out)
            emit({ name: name, rssKb: rss ? Number(rss[1]) : -1,
                   cpuTicks: cpu ? Number(cpu[1]) + Number(cpu[2]) : -1, spawnsTotal: Secret._job })
            ticker.go(0)
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

    // Starts once the demo profile is connected and its first data is in.
    Timer {
        interval: 6000
        running: runner.active && runner.plasmoidRoot !== null && runner.plasmoidRoot.session.connection.configured
        repeat: false
        onTriggered: runner.start()
    }

    Component.onCompleted: load()
}
