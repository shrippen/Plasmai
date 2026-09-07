import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi

Kirigami.Page {
    id: page
    title: ""
    background: Rectangle { color: root.bgWindow }
    property bool busy: false
    property var editTs: null
    readonly property bool editMode: editTs !== null
    property bool creatingProject: false
    property bool creatingActivity: false
    property string newEntityName: ""
    function projectModelIndex() { if (!editTs) return -1; var pid = KimaiApi.projectId(editTs) || ""; for (var i = 0; i < root.projects.length; i++) { if (String(root.projects[i].id) === String(pid)) return i }; return -1 }
    function activityModelIndex() { if (!editTs) return -1; var aid = KimaiApi.activityId(editTs) || ""; for (var i = 0; i < root.allActivities.length; i++) { if (String(root.allActivities[i].id) === String(aid)) return i }; return -1 }
    function calcDuration() { var d = new Date(dateField.text + "T" + timeField.text + ":00"); var et = endDateField.text; var e = et.length > 0 ? new Date(et + "T" + (endTimeField.text || "00:00") + ":00") : null; var sec = (e && !isNaN(e.getTime()) && !isNaN(d.getTime())) ? Math.max(0, Math.floor((e - d) / 1000)) : 0; var h = Math.floor(sec / 3600); var m = Math.floor((sec % 3600) / 60); return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m }
    function doSave() { busy = true; var url = TimeTracker.resolveUrl(root.activeProfile); var stamp = dateField.text + "T" + timeField.text + ":00"; var proj = projectCombo.model[projectCombo.currentIndex].id; var act = activityCombo.model[activityCombo.currentIndex].id; var fields = { projectId: proj, activityId: act, begin: KimaiApi.localDateTimeString(new Date(stamp)), description: descField.text }; if (endDateField.text.length > 0) { var eDate = new Date(endDateField.text + "T" + (endTimeField.text || "00:00") + ":00"); if (!isNaN(eDate.getTime())) fields.end = KimaiApi.localDateTimeString(eDate) }; var editId = editMode && editTs ? editTs.id : null; var cb = function(r) { busy = false; if (r.ok) pageStack.pop() }; if (editId) root.tracker.patchTimesheet(url, root.apiToken, editId, fields, cb); else root.tracker.createTimesheet(url, root.apiToken, fields, cb) }
    function activityPickerModel() { if (projectCombo.currentIndex < 0 || !root.projects[projectCombo.currentIndex]) return root.allActivities.map(function(a) { return { name: a.name || "?", id: String(a.id) } }); var pid = root.projects[projectCombo.currentIndex].id; var acts = root.activities.filter(function(a) { return String(a.projectId) === String(pid) }); if (!acts.length) acts = root.allActivities; return acts.map(function(a) { return { name: a.name || "?", id: String(a.id) } }) }
    function createProject() { page.busy = true; root.tracker.createProject(TimeTracker.resolveUrl(root.activeProfile), root.apiToken, { name: page.newEntityName, customer: "" }, function(r) { page.busy = false; if (r.ok) { root.refreshAll(); page.creatingProject = false } }) }
    function createActivity() { page.busy = true; var pid = projectCombo.currentIndex >= 0 ? root.projects[projectCombo.currentIndex].id : ""; root.tracker.createActivity(TimeTracker.resolveUrl(root.activeProfile), root.apiToken, { name: page.newEntityName, project: pid }, function(r) { page.busy = false; if (r.ok) { page.creatingActivity = false } }) }

    Component.onCompleted: {
        if (editTs) {
            dateField.text = editTs.begin ? Qt.formatDate(new Date(editTs.begin), "yyyy-MM-dd") : Qt.formatDate(new Date(), "yyyy-MM-dd")
            timeField.text = editTs.begin ? Qt.formatTime(new Date(editTs.begin), "HH:mm") : Qt.formatTime(new Date(), "HH:mm")
            endDateField.text = editTs.end ? Qt.formatDate(new Date(editTs.end), "yyyy-MM-dd") : ""
            endTimeField.text = editTs.end ? Qt.formatTime(new Date(editTs.end), "HH:mm") : ""
            descField.text = editTs.description || ""
            Qt.callLater(function() { var pi = page.projectModelIndex(); if (pi >= 0) projectCombo.currentIndex = pi })
            Qt.callLater(function() { Qt.callLater(function() { var ai = page.activityModelIndex(); if (ai >= 0) activityCombo.currentIndex = ai }) })
        }
    }
    Connections {
        target: Qt.inputMethod
        function onKeyboardRectangleChanged() {
            Qt.callLater(function() { page.ensureFocusedVisible() })
        }
    }

    function ensureFocusedVisible() {
        var fi = root.activeFocusItem
        if (!fi || !meFlickable) return
        var kb = Qt.inputMethod.keyboardRectangle
        var kbHeight = kb ? kb.height : 0
        if (kbHeight <= 0) return
        var pos = meFlickable.mapFromItem(fi, 0, 0)
        var itemBottom = pos.y + fi.height + 12
        var visibleBottom = meFlickable.height - kbHeight
        if (itemBottom > visibleBottom) {
            meFlickable.contentY += (itemBottom - visibleBottom)
        } else if (pos.y < meFlickable.contentY) {
            meFlickable.contentY = pos.y
        }
    }

    Flickable {
        id: meFlickable
        anchors.fill: parent
        contentHeight: formCol.implicitHeight + 32
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: formCol
        width: parent.width; anchors.margins: 16; spacing: 12

        Kirigami.Heading { level: 1; text: editTs ? i18n("Edit entry") : i18n("Add entry"); color: root.clrText }

        // ── Connection status ──
        RowLayout { Layout.fillWidth: true; spacing: 6
            QQC2.Label { text: !root.isConfigured ? "⊘" : root.connectionState === "error" ? "⚠" : "✓"; font.pointSize: 14
                color: !root.isConfigured ? root.clrTextMuted : root.connectionState === "error" ? root.clrDanger : root.clrPositive; Layout.preferredWidth: 20; horizontalAlignment: Text.AlignHCenter }
            QQC2.Label { text: root.activeProfile ? (root.activeProfile.url || root.activeProfile.provider || "") : ""; font.pointSize: 11; color: root.clrTextSec; elide: Text.ElideRight; Layout.fillWidth: true }
        }

        QQC2.Label { text: page.editMode ? i18n("Edit the stopped entry.") : i18n("Create a completed entry with project, activity, and time range."); wrapMode: Text.WordWrap; font.pointSize: 12; color: root.clrTextSec }

        // ── Project picker ──
        RowLayout { spacing: 4
            QQC2.ComboBox { id: projectCombo; Layout.fillWidth: true; textRole: "name"
                model: root.projects.map(function(p) { return { name: p.name || "?", id: String(p.id) } })
                currentIndex: page.editMode ? page.projectModelIndex() : -1
                displayText: currentIndex >= 0 ? model[currentIndex].name : i18n("Project") }
            QQC2.ToolButton { contentItem: QQC2.Label { text: "＋"; font.pointSize: 16; color: root.clrAccent }
                visible: root.providerMeta && root.providerMeta.createEntities
                onClicked: { page.creatingProject = true; page.creatingActivity = false; page.newEntityName = "" } }
        }
        RowLayout { visible: page.creatingProject; spacing: 4
            QQC2.TextField { id: newProjectField; Layout.fillWidth: true; placeholderText: i18n("New project name"); color: root.clrText; placeholderTextColor: root.clrTextMuted }
            QQC2.Button { text: i18n("Create"); onClicked: page.createProject() }
            QQC2.ToolButton { contentItem: QQC2.Label { text: "✕"; font.pointSize: 14; color: root.clrTextSec }
                onClicked: page.creatingProject = false }
        }

        // ── Activity picker ──
        RowLayout { spacing: 4
            QQC2.ComboBox { id: activityCombo; Layout.fillWidth: true; textRole: "name"
                model: page.activityPickerModel()
                currentIndex: page.editMode ? page.activityModelIndex() : -1
                displayText: currentIndex >= 0 ? model[currentIndex].name : i18n("Activity") }
            QQC2.ToolButton { contentItem: QQC2.Label { text: "＋"; font.pointSize: 16; color: root.clrAccent }
                visible: root.providerMeta && root.providerMeta.createEntities
                onClicked: { page.creatingActivity = true; page.creatingProject = false; page.newEntityName = "" } }
        }
        RowLayout { visible: page.creatingActivity; spacing: 4
            QQC2.TextField { id: newActivityField; Layout.fillWidth: true; placeholderText: i18n("New activity name"); color: root.clrText; placeholderTextColor: root.clrTextMuted }
            QQC2.Button { text: i18n("Create"); onClicked: page.createActivity() }
            QQC2.ToolButton { contentItem: QQC2.Label { text: "✕"; font.pointSize: 14; color: root.clrTextSec }
                onClicked: page.creatingActivity = false }
        }

        // ── Begin ──
        QQC2.Label { text: i18n("Begin"); font.bold: true; color: root.clrText }
        RowLayout { Layout.fillWidth: true; spacing: 4
            QQC2.TextField { id: dateField; Layout.fillWidth: true; placeholderText: "YYYY-MM-DD"
                text: Qt.formatDate(new Date(), "yyyy-MM-dd"); color: root.clrText; placeholderTextColor: root.clrTextMuted }
            QQC2.TextField { id: timeField; Layout.fillWidth: true; placeholderText: "HH:mm"
                text: Qt.formatTime(new Date(), "HH:mm"); color: root.clrText; placeholderTextColor: root.clrTextMuted }
        }

        // ── End ──
        QQC2.Label { text: i18n("End"); font.bold: true; color: root.clrText }
        RowLayout { Layout.fillWidth: true; spacing: 4
            QQC2.TextField { id: endDateField; Layout.fillWidth: true; placeholderText: "YYYY-MM-DD"; color: root.clrText; placeholderTextColor: root.clrTextMuted }
            QQC2.TextField { id: endTimeField; Layout.fillWidth: true; placeholderText: "HH:mm"; color: root.clrText; placeholderTextColor: root.clrTextMuted }
        }

        QQC2.Label { text: i18n("Duration: %1", page.calcDuration()); font.pointSize: 12; color: root.clrTextSec }

        QQC2.TextField { id: descField; Layout.fillWidth: true; placeholderText: i18n("Description (optional)"); color: root.clrText; placeholderTextColor: root.clrTextMuted }

        RowLayout { Layout.fillWidth: true; spacing: 4
            QQC2.Button { text: page.busy ? i18n("Saving…") : (page.editMode ? i18n("Save changes") : i18n("Save entry")); Layout.fillWidth: true
                enabled: !page.busy && root.isConfigured && projectCombo.currentIndex >= 0 && activityCombo.currentIndex >= 0
                onClicked: page.doSave()
                contentItem: RowLayout { spacing: 4; QQC2.Label { text: parent.parent.text; color: "white" } }
                background: Rectangle { radius: 6; color: parent.down ? Qt.darker(root.clrAccent, 1.2) : (parent.hovered ? Qt.lighter(root.clrAccent, 1.1) : root.clrAccent) } }
            QQC2.Button { text: i18n("Cancel"); onClicked: pageStack.pop() }
        }
    }
    } // Flickable
}
