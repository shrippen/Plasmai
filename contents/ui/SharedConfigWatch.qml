import QtQuick
import Qt.labs.folderlistmodel

/**
 * Tells when `fileName` in `folder` was written: a directory watcher
 * (FolderListModel), no shell process. Writers move a new file into place
 * (sharedConfig.sh: mktemp + mv), which changes the folder.
 *
 *   folder changes ─▶ model rows/data change ─▶ changed()   (not for the first load)
 */
QtObject {
    id: watch

    property url folder
    property string fileName

    signal changed()

    /** The first listing of the folder is not a change. */
    property bool listed: false

    readonly property FolderListModel model: FolderListModel {
        folder: watch.folder
        nameFilters: [watch.fileName]
        showDirs: false
        showDotAndDotDot: false
        onStatusChanged: {
            if (status === FolderListModel.Ready) {
                Qt.callLater(function() { watch.listed = true })
            }
        }
    }

    function report() {
        if (listed) {
            changed()
        }
    }

    readonly property Connections modelSignals: Connections {
        target: watch.model
        function onRowsInserted() { Qt.callLater(watch.report) }
        function onRowsRemoved() { Qt.callLater(watch.report) }
        function onDataChanged() { Qt.callLater(watch.report) }
        function onModelReset() { Qt.callLater(watch.report) }
    }
}
