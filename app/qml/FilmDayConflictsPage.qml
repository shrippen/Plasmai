import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/filmDays.js" as FilmDays
import "../contents/code/filmDaySync.js" as FilmDaySync
import "shared"

/**
 * P6: film days whose server values differ from this device after the
 * migration, side by side; per day keep the server values or send the local
 * ones. Emits closed() when the page is left so the film day page reloads.
 */
Kirigami.Page {
    id: page
    title: i18n("Review film days")

    property var items: []
    property bool loading: false
    property bool busy: false

    signal closed()

    function reload() {
        page.loading = true
        var ctx = root.filmDayContext()
        FilmDaySync.loadConflicts(ctx, FilmDaySync.conflictCandidates(ctx), function(r) {
            page.loading = false
            page.items = r.items
            if (r.localMap) root.persistFilmDayKeys({ filmDaysJson: FilmDays.serialize(r.localMap) })
        })
    }

    function resolve(item, useLocal) {
        if (page.busy) return
        page.busy = true
        FilmDaySync.resolveConflict(root.filmDayContext(), item, useLocal, function(r) {
            page.busy = false
            if (!r.ok) {
                root.showPassiveNotification(i18n("The film day could not be sent: %1",
                                                  (r.error && r.error.detail) || ApiErrors.text(r.error)))
                return
            }
            root.persistFilmDayKeys({ filmDaysJson: FilmDays.serialize(r.localMap) })
            page.items = page.items.map(function(it) {
                if (it.key !== item.key) return it
                var copy = {}
                for (var k in it) copy[k] = it[k]
                copy.state = useLocal ? "resolvedLocal" : "resolvedServer"
                return copy
            })
        })
    }

    Component.onCompleted: reload()
    Component.onDestruction: page.closed()

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: pageScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            FilmDayConflicts {
                Layout.fillWidth: true
                items: page.items
                loading: page.loading
                busy: page.busy
                projectNameOf: function(projectId) {
                    var p = root.projectById(projectId)
                    return p ? String(p.name || "") : ""
                }
                currencyOf: function(projectId) {
                    return KimaiApi.customerCurrencyOfProject(root.projectById(projectId), root.customers)
                }
                onResolveRequested: function(item, useLocal) { page.resolve(item, useLocal) }
                onCloseRequested: pageStack.pop()
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.largeSpacing }
        }
    }
}
