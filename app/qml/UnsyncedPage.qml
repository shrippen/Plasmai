import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/offline.js" as Offline
import "shared"
import "Kante"

/** Changes made offline that are not on the server yet (offline.js outbox). */
Kirigami.Page {
    id: page
    objectName: "unsyncedPage"
    KantePageTitle { page: page }
    title: i18n("Not synced")

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        anchors.rightMargin: -page.rightPadding
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.min((pageScroll.availableWidth - page.rightPadding), Kirigami.Units.gridUnit * 28)
            x: Math.max(0, ((pageScroll.availableWidth - page.rightPadding) - width) / 2)
            spacing: Kirigami.Units.largeSpacing

            UnsyncedList {
                Layout.fillWidth: true
                ops: root.offlineRevision >= 0 && root.offlineSession ? Offline.ops(root.offlineSession) : []
                projects: root.projects
                activities: root.allActivities
                activitiesByProject: root.activitiesByProject
                onRetryRequested: function(opId) { Offline.retry(root.offlineSession, opId, function() { root.refreshAll() }) }
                onOverwriteRequested: function(opId) { Offline.overwrite(root.offlineSession, opId, function() { root.refreshAll() }) }
                onDiscardRequested: function(opId) { Offline.discard(root.offlineSession, opId); root.refreshAll() }
            }
        }
    }
}
