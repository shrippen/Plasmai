import QtQuick
import org.kde.kirigami as Kirigami
import "../code/secret.js" as Secret
import "../code/kimaiApi.js" as KimaiApi

/**
 * Landing-page screenshots, only when a plan file exists:
 *   $XDG_CONFIG_HOME/com.github.shrippen.plasmai/screenshots.json
 *   { "dir": "/out", "shots": [ { "name": "timer", "view": "main|manual|stats|filmday|edit|datepicker|timepicker|create|offline|unsynced|online" } ] }
 * demo/shots.sh writes it into a scratch config home together with a demo profile, then
 * runs plasmoidviewer offscreen. Each view is grabbed with grabToImage into dir/name.png
 * (popup views: the whole X screen with ImageMagick's import, use a planar viewer),
 * then the viewer quits ("PLASMAI_SCREENSHOT_DONE" in the log). Without the file: nothing.
 */
Item {
    id: runner

    property var plasmoidRoot: null
    property var execSource: null
    property var plan: null
    property var queue: []
    property int shotCount: 0
    readonly property bool active: plan !== null

    function trace(msg) {
        console.warn(msg)
    }

    function load() {
        var file = "\"${XDG_CONFIG_HOME:-$HOME/.config}/com.github.shrippen.plasmai/screenshots.json\""
        Secret._run(execSource, "cat " + file + " 2>/dev/null", function(data) {
            var parsed = Secret.parseJsonPayload(data && data.stdout)
            if (parsed && parsed.dir && parsed.shots) {
                runner.plan = parsed
                trace("PLASMAI_SCREENSHOT_START " + parsed.dir)
            }
        })
    }

    function start() {
        var q = [{ act: "expand" }]
        for (var i = 0; i < plan.shots.length; ++i) {
            q.push({ act: "view", value: plan.shots[i].view || "main" })
            q.push({ act: "shot", name: plan.shots[i].name })
        }
        q.push({ act: "done" })
        queue = q
        step()
    }

    function step() {
        if (queue.length === 0) {
            return
        }
        var item = queue[0]
        queue = queue.slice(1)
        var wait = 300
        var r = plasmoidRoot
        switch (item.act) {
        case "expand":
            r.expanded = true
            wait = 3000
            break
        case "view":
            if (item.value === "manual") {
                r.openManualEntry()
            } else if (item.value === "stats") {
                r.openStatsView()
            } else if (item.value === "filmday") {
                r.openFilmDayView()
            } else if (item.value === "edit") {
                r.openActiveEdit()
            } else if (item.value === "datepicker") {
                // In the add-entry view: the begin date's calendar.
                r.openManualEntry()
                Qt.callLater(function() { runner.callFirst(r.fullRepresentationItem, "openPicker", []) })
            } else if (item.value === "timepicker") {
                r.openManualEntry()
                Qt.callLater(function() { runner.callFirst(r.fullRepresentationItem, "openFor", [9, 30]) })
            } else if (item.value === "create") {
                r.openManualEntry()
                Qt.callLater(function() {
                    var d = runner.findFirst(r.fullRepresentationItem, "resetForMode")
                    if (d) {
                        d.resetForMode("project")
                        d.open()
                    }
                })
            } else if (item.value === "offline") {
                // The network goes away (every request fails), then: stop, start another activity.
                var route = KimaiApi.urlRoute
                KimaiApi.setUrlRoute({ original: route, handles: route.handles, token: route.token,
                                       request: function() { return runner.deadRequest() } })
                r.returnToMainView()
                r.refreshAll(true)
                Qt.callLater(function() {
                    r.stopTracking(false)
                    Qt.callLater(function() { r.startTracking(10, 21, "Harbour Lights", "Vorproduktion", "offline") })
                })
            } else if (item.value === "stop") {
                r.returnToMainView()
                r.stopTracking(false)
            } else if (item.value === "unsynced") {
                r.openUnsyncedView()
            } else if (item.value === "online") {
                if (KimaiApi.urlRoute && KimaiApi.urlRoute.original) {
                    KimaiApi.setUrlRoute(KimaiApi.urlRoute.original)
                }
                r.returnToMainView()
                r.refreshAll(true)
            } else {
                r.returnToMainView()
            }
            wait = 3500
            break
        case "shot": {
            // Popups are drawn outside the representation item: take the whole (X) screen.
            if (item.name.indexOf("picker") >= 0 || item.name.indexOf("create") >= 0) {
                trace("PLASMAI_SCREENSHOT " + item.name + " screen")
                Secret._run(execSource, "import -window root '" + runner.plan.dir + "/" + item.name + ".png'", function() {
                    runner.shotCount += 1
                    ticker.restart()
                })
                return
            }
            var target = r.fullRepresentationItem
            trace("PLASMAI_SCREENSHOT " + item.name + " " + Math.round(target.width) + "x" + Math.round(target.height))
            var ok = target.grabToImage(function(result) {
                result.saveToFile(runner.plan.dir + "/" + item.name + ".png")
                runner.shotCount += 1
                ticker.restart()
            })
            if (!ok) {
                trace("PLASMAI_SCREENSHOT_FAILED " + item.name)
                ticker.restart()
            }
            return
        }
        case "done":
            trace("PLASMAI_SCREENSHOT_DONE " + shotCount)
            Qt.quit()
            return
        }
        ticker.interval = wait
        ticker.restart()
    }

    // A request that fails like a lost network (status 0), for the offline views.
    function deadRequest() {
        var x = {
            readyState: 0, status: 0, statusText: "", responseText: "",
            open: function() {}, setRequestHeader: function() {}, abort: function() {},
            getResponseHeader: function() { return null },
            send: function() {
                x.readyState = 4
                if (x.onreadystatechange) {
                    x.onreadystatechange()
                }
            }
        }
        return x
    }

    // First item under `item` (children, then popups' content) with a function `name`;
    // `openFor` of the time picker takes two arguments, the date picker's one.
    function findFirst(item, name, argc) {
        if (!item) {
            return null
        }
        if (typeof item[name] === "function" && (argc === undefined || item[name].length === argc)) {
            return item
        }
        var kids = (item.children || []).concat(item.data || [])
        for (var i = 0; i < kids.length; ++i) {
            var found = kids[i] !== item ? findFirst(kids[i], name, argc) : null
            if (found) {
                return found
            }
        }
        return null
    }

    function callFirst(item, name, args) {
        var target = findFirst(item, name, args.length || undefined)
        if (target) {
            target[name].apply(target, args)
        } else {
            trace("PLASMAI_SCREENSHOT_NOTFOUND " + name)
        }
    }

    Timer {
        id: ticker
        repeat: false
        onTriggered: runner.step()
    }

    // Starts once the demo profile is connected and the first data is in.
    Timer {
        interval: 6000
        running: runner.active && runner.plasmoidRoot && runner.plasmoidRoot.isConfigured
        repeat: false
        onTriggered: runner.start()
    }

    // The flyout frame is drawn outside the grabbed item; give the grab a real ground.
    Rectangle {
        parent: runner.active && runner.plasmoidRoot ? runner.plasmoidRoot.fullRepresentationItem : null
        anchors.fill: parent
        z: -100
        visible: runner.active
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        color: Kirigami.Theme.backgroundColor
    }

    Component.onCompleted: load()
}
