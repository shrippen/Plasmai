import QtQuick
import org.kde.kirigami as Kirigami
import "../code/secret.js" as Secret

/**
 * Landing-page screenshots, only when a plan file exists:
 *   $XDG_CONFIG_HOME/com.github.shrippen.plasmai/screenshots.json
 *   { "dir": "/out", "shots": [ { "name": "timer", "view": "main|manual|stats|filmday" } ] }
 * demo/shots.sh writes it into a scratch config home together with a demo profile, then
 * runs plasmoidviewer offscreen. Each view is grabbed with grabToImage into dir/name.png,
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
            } else {
                r.returnToMainView()
            }
            wait = 3500
            break
        case "shot": {
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
