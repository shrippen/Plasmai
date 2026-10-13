import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "shared"
import "Kante"

/** Changes made offline that are not on the server yet (offline.js outbox). */
Kirigami.Page {
    id: page
    readonly property QtObject session: root.session
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
                ops: session.sync.ops
                projects: session.catalog.projects
                activities: session.catalog.activities
                activitiesByProject: session.catalog.activitiesByProject
                onRetryRequested: function(opId) { session.sync.retry(opId) }
                onOverwriteRequested: function(opId) { session.sync.overwrite(opId) }
                onDiscardRequested: function(opId) { session.sync.discard(opId) }
            }
        }
    }
}
