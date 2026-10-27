import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "../code/secret.js" as Secret

/**
 * The executable engine for secret.js: one DataSource per command, destroyed
 * once it answered. A long-lived DataSource keeps every source with its data
 * after disconnectSource, and store commands carry up to 30 KB of JSON each,
 * so a shared one grew plasmashell by gigabytes a day.
 */
QtObject {
    id: exec

    property var jobs: ({})

    readonly property Component job: Component {
        P5Support.DataSource {
            engine: "executable"
        }
    }

    function connectSource(source) {
        const ds = job.createObject(exec)
        jobs[source] = ds
        ds.newData.connect(function(sourceName, data) {
            Secret.handleData(exec, sourceName, data)
        })
        ds.connectSource(source)
    }

    function disconnectSource(source) {
        const ds = jobs[source]
        if (!ds) {
            return
        }
        delete jobs[source]
        ds.disconnectSource(source)
        ds.destroy()
    }

    Component.onDestruction: Secret.cancelAll(exec)
}
