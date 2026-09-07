import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi

Kirigami.Page {
    id: page; title: ""
    padding: 0
    background: Rectangle { color: root.bgWindow }

    property bool editingActive: false
    property var editActModel: []
    property string editDate: ""
    property string editTime: ""
    property string editDesc: ""

    function editProjectIndex() { for(var i=0;i<root.projects.length;i++){if(root.projects[i].name===root.currentProject)return i} return -1 }
    function editActivityIndex() { for(var i=0;i<editActModel.length;i++){if(editActModel[i].name===root.currentActivity)return i} return -1 }
    function workSummaryText() {
        var bits = []
        bits.push(i18n("Today %1", KimaiApi.formatDurationShort(root.todayLiveSeconds)))
        bits.push(i18n("Week %1", KimaiApi.formatDurationShort(root.weekLiveSeconds)))
        return bits.join(" · ")
    }
    function remainingText() {
        if (!root.hasWorkContract) return ""
        var bits = []
        if (root.todayTargetSeconds > 0) bits.push(root.remainingTodayText())
        if (root.weekTargetSeconds > 0) bits.push(root.remainingWeekText())
        return bits.join(" · ")
    }
    function isOverTime() {
        return root.hasWorkContract && (root.remainingTodaySeconds < 0 || root.remainingWeekSeconds < 0)
    }
    function connIcon() { return !root.isConfigured ? "⊘" : root.connectionState === "error" ? "⚠" : "✓" }
    function connColor() { return !root.isConfigured ? root.clrTextMuted : root.connectionState === "error" ? root.clrDanger : root.clrPositive }
    function openEdit() { if (root.isTracking && root.activeTimesheet) { editingActive = true; refreshEditActivities() } }
    function saveEdit() { var f={}; if(editProj.currentIndex>=0)f.project=editProj.model[editProj.currentIndex].id; if(editAct.currentIndex>=0)f.activity=editAct.model[editAct.currentIndex].id; var d=new Date(page.editDate+"T"+page.editTime+":00"); if(!isNaN(d.getTime()))f.begin=KimaiApi.localDateTimeString(d); f.description=page.editDesc; root.patchActiveEntry(f); editingActive=false }
    function refreshEditActivities() {
        if(!editingActive||editProj.currentIndex<0||!root.projects[editProj.currentIndex]){editActModel=[];return}
        var pid=root.projects[editProj.currentIndex].id, a=root.activities.filter(function(x){return String(x.projectId)===String(pid)}); if(!a.length)a=root.allActivities
        editActModel=a.map(function(x){return{name:x.name||"?",id:String(x.id)}})
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 32
        clip: true
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout { id: col; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16; spacing: 10

            // ══════ HEADER ══════
            RowLayout { Layout.fillWidth: true; spacing: 8
                QQC2.Label { text: i18n("Plasmai"); font.bold: true; font.pointSize: 16; color: root.clrText; Layout.fillWidth: true }
                QQC2.ToolButton {
                    visible: root.isConfigured
                    contentItem: QQC2.Label { text: "＋"; font.pointSize: 20; color: root.clrAccent; horizontalAlignment: Text.AlignHCenter }
                    Layout.preferredWidth: 40; Layout.preferredHeight: 40
                    background: Rectangle { radius: 8; color: parent.hovered ? Qt.rgba(0.15, 0.68, 0.38, 0.15) : "transparent" }
                    onClicked: pageStack.push(manualPageComponent)
                }
                QQC2.ToolButton {
                    visible: root.isConfigured
                    contentItem: QQC2.Label { text: "\u2261"; font.pointSize: 20; color: root.clrTextSec; horizontalAlignment: Text.AlignHCenter; font.bold: true }
                    Layout.preferredWidth: 40; Layout.preferredHeight: 40
                    background: Rectangle { radius: 8; color: parent.hovered ? Qt.rgba(0.15, 0.68, 0.38, 0.15) : "transparent" }
                    onClicked: pageStack.push(statsPageComponent)
                }
            }

            // ══════ CONNECTION STATUS ══════
            RowLayout { Layout.fillWidth: true; spacing: 6
                QQC2.Label { text: connIcon(); color: connColor(); font.pointSize: 11 }
                QQC2.Label {
                    text: {
                        if (!root.isConfigured) return i18n("Not configured")
                        if (root.connectionState === "connecting") return i18n("Connecting…")
                        if (root.connectionState === "error") return i18n("Connection problem")
                        var profileName = root.activeProfile ? root.activeProfile.name || "" : ""
                        var url = root.activeProfile ? root.activeProfile.url || "" : ""
                        if (profileName.length > 0) return i18n("Verbunden mit %1 (%2)", url, profileName)
                        return i18n("Verbunden mit %1", url)
                    }
                    color: root.clrTextSec; font.pointSize: 11; elide: Text.ElideRight
                    Layout.fillWidth: true; maximumLineCount: 1
                }
                QQC2.BusyIndicator {
                    running: root.isBusy || root.connectionState === "connecting"
                    visible: running; Layout.preferredWidth: 16; Layout.preferredHeight: 16
                }
            }

            // ══════ TIMER CARD ══════
            Rectangle {
                Layout.fillWidth: true
                radius: 12
                height: timerCol.implicitHeight + 24
                color: root.isTracking ? root.bgCardTracking : root.bgCard
                border.width: root.isTracking ? 2 : 1
                border.color: root.isTracking ? root.clrBorderTracking : root.clrBorder

                ColumnLayout { id: timerCol; anchors.fill: parent; anchors.margins: 12; spacing: 8

                    // ── Timer row: big time + stop ──
                    RowLayout { Layout.fillWidth: true; spacing: 12
                        QQC2.Label {
                            text: KimaiApi.formatDuration(root.elapsedSeconds)
                            font.family: "monospace"; font.pointSize: 30; font.bold: true
                            color: root.clrAccent
                            Layout.fillWidth: true
                        }
                        QQC2.Label {
                            text: root.currentCustomer || ""
                            color: root.clrTextSec; font.pointSize: 12
                            visible: root.isTracking && root.currentCustomer.length > 0
                        }
                        QQC2.Button {
                            visible: root.isTracking
                            text: i18n("Stopp")
                            implicitHeight: 40
                            onClicked: root.confirmBeforeStop ? confirmDialog.open() : root.stopTracking()
                            contentItem: RowLayout { spacing: 6; anchors.centerIn: parent
                                Rectangle { width: 12; height: 12; radius: 2; color: "white"
                                    QQC2.Label { anchors.centerIn: parent; text: "■"; font.pointSize: 8; color: root.clrDanger } }
                                QQC2.Label { text: i18n("Stopp"); color: "white"; font.bold: true }
                            }
                            background: Rectangle { radius: 8; color: parent.down ? Qt.darker(root.clrDanger, 1.2) : (parent.hovered ? Qt.lighter(root.clrDanger, 1.1) : Qt.rgba(0.91, 0.30, 0.24, 0.85)) }
                        }
                    }

                    // ── Project / Activity row ──
                    RowLayout { visible: root.isTracking; Layout.fillWidth: true; spacing: 6
                        Rectangle { width: 10; height: 14; radius: 5; color: root.currentCustomerColor || KimaiApi.DEFAULT_CUSTOMER_COLOR; border.width: 1; border.color: Qt.rgba(0,0,0,0.18) }
                        QQC2.Label { text: root.currentProject || ""; color: root.clrText; font.bold: true; font.pointSize: 12; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                        QQC2.Label { text: "·"; color: root.clrTextMuted; font.pointSize: 12; Layout.preferredWidth: 12 }
                        QQC2.Label { text: root.currentActivity || ""; color: root.clrTextSec; font.pointSize: 12; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                        QQC2.ToolButton {
                            contentItem: QQC2.Label { text: "✎"; font.pointSize: 12; color: root.clrTextSec }
                            onClicked: openEdit(); Layout.preferredWidth: 28; Layout.minimumWidth: 28; Layout.maximumWidth: 28; Layout.preferredHeight: 28
                        }
                    }

                    // ── Inline activity editor (when editing active entry) ──
                    ColumnLayout { visible: editingActive; spacing: 6
                        RowLayout { spacing: 4
                            QQC2.ComboBox { id: editProj; Layout.fillWidth: true; textRole: "name"; model: root.projects; currentIndex: page.editProjectIndex()
                                onCurrentIndexChanged: page.refreshEditActivities() }
                        }
                        RowLayout { spacing: 4
                            QQC2.ComboBox { id: editAct; Layout.fillWidth: true; textRole: "name"; model: page.editActModel; currentIndex: page.editActivityIndex() }
                        }
                        RowLayout { spacing: 4
                            QQC2.TextField { id: editDateField; Layout.fillWidth: true; placeholderText: "YYYY-MM-DD"
                                text: Qt.formatDate(new Date(), "yyyy-MM-dd"); color: root.clrText; placeholderTextColor: root.clrTextMuted
                                Component.onCompleted: { page.editDate = text }
                                background: Rectangle { radius: 6; color: root.bgInput; border.width: 1; border.color: root.clrBorder } }
                            QQC2.TextField { id: editTimeField; Layout.fillWidth: true; placeholderText: "HH:mm"
                                text: Qt.formatTime(new Date(), "HH:mm"); color: root.clrText; placeholderTextColor: root.clrTextMuted
                                Component.onCompleted: { page.editTime = text }
                                background: Rectangle { radius: 6; color: root.bgInput; border.width: 1; border.color: root.clrBorder } }
                        }
                        QQC2.TextField { id: editDescField; Layout.fillWidth: true; placeholderText: i18n("Description")
                            text: root.currentDescription; color: root.clrText; placeholderTextColor: root.clrTextMuted
                            onEditingFinished: page.editDesc = text
                            background: Rectangle { radius: 6; color: root.bgInput; border.width: 1; border.color: root.clrBorder } }
                        RowLayout { spacing: 6
                            QQC2.Button { text: i18n("Save"); Layout.fillWidth: true; onClicked: page.saveEdit()
                                contentItem: RowLayout { spacing: 4; anchors.centerIn: parent; QQC2.Label { text: parent.parent.text; color: "white" } }
                                background: Rectangle { radius: 6; color: parent.down ? Qt.darker(root.clrAccent, 1.2) : root.clrAccent } }
                            QQC2.Button { text: i18n("Cancel"); onClicked: editingActive = false }
                        }
                    }

                    // ── Work summary ──
                    RowLayout { Layout.fillWidth: true; spacing: 10
                        QQC2.Label { text: workSummaryText(); color: root.clrTextSec; font.pointSize: 11; Layout.fillWidth: true }
                        QQC2.Label {
                            visible: root.hasWorkContract
                            text: remainingText()
                            color: isOverTime() ? root.clrWarning : root.clrTextSec
                            font.pointSize: 11; font.bold: isOverTime()
                        }
                    }

                }
            }

            // ══════ DAY SPARKLINE BAR ══════
            Item {
                visible: root.isConfigured
                Layout.fillWidth: true; Layout.topMargin: 8; implicitHeight: sparkBar.height
                property var sparkModel: (function() { var _f = root.sparklineNowTick; return root.todayTimesheets && root.todayTimesheets.length > 0 ? KimaiApi.buildDaySparklineModel(root.todayTimesheets, root.todayTargetSeconds, root.workDayBegin, root.workDayEnd, Date.now()) : null })()
                Canvas { id: sparkBar; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 44
                    property var sm: parent.sparkModel
                    onPaint: {
                        var ctx = getContext("2d"); ctx.reset()
                        var w = width, h = height
                        var barH = 14, barY = 6
                        if (!sm || !sm.segments) {
                            // Empty state: draw subtle background track
                            ctx.fillStyle = Qt.rgba(1,1,1,0.06)
                            ctx.beginPath(); ctx.roundedRect(0, barY, w, barH, 3, 3); ctx.fill()
                            return
                        }
                        var vs = sm.viewStart, ve = sm.viewEnd, span = ve - vs
                        if (span <= 0) return
                        // Background track
                        ctx.fillStyle = Qt.rgba(1,1,1,0.12); ctx.beginPath(); ctx.roundedRect(0, barY, w, barH, 3, 3); ctx.fill()
                        // Business hours outline
                        var bs = (sm.businessStart - vs) / span, be = (sm.businessEnd - vs) / span
                        ctx.strokeStyle = Qt.rgba(1,1,1,0.28); ctx.lineWidth = 1
                        ctx.strokeRect(Math.max(0, bs * w), barY, Math.min(w, (be - bs) * w), barH)
                        // Work segments
                        for (var i = 0; i < sm.segments.length; i++) {
                            var seg = sm.segments[i]
                            var x0 = Math.max(0, (seg.start - vs) / span * w)
                            var x1 = Math.min(w, (seg.end - vs) / span * w)
                            if (x1 <= x0) continue
                            ctx.fillStyle = seg.overtime ? root.clrWarning : root.clrAccent
                            ctx.beginPath(); ctx.roundedRect(x0, barY + 1, x1 - x0, barH - 2, 2, 2); ctx.fill()
                        }
                        // Now indicator
                        var nowX = (sm.now - vs) / span * w
                        if (nowX >= 0 && nowX <= w) {
                            ctx.strokeStyle = root.clrText; ctx.lineWidth = 2
                            ctx.beginPath(); ctx.moveTo(nowX, barY - 2); ctx.lineTo(nowX, barY + barH + 2); ctx.stroke()
                            ctx.fillStyle = root.clrText; ctx.beginPath(); ctx.arc(nowX, barY - 2, 3, 0, 2 * Math.PI); ctx.fill()
                        }
                        // 3h labels
                        ctx.fillStyle = root.clrTextMuted; ctx.font = "9px sans-serif"; ctx.textAlign = "center"
                        var hourSpan = span * 24
                        var step = hourSpan <= 12 ? 2 : (hourSpan <= 24 ? 3 : 6)
                        var firstH = Math.floor(vs * 24 / step) * step
                        for (var hr = firstH; hr <= 24; hr += step) {
                            var frac = hr / 24
                            if (frac < vs || frac > ve) continue
                            var lx = (frac - vs) / span * w
                            ctx.fillText((hr < 10 ? "0" : "") + hr, lx, barY + barH + 14)
                        }
                    }
                    Connections { target: root; function onSparklineNowTickChanged() { sparkBar.requestPaint() } }
                    Component.onCompleted: requestPaint()
                }
            }

            // ══════ DESCRIPTION FIELD ══════
            Rectangle {
                Layout.fillWidth: true; height: descField.implicitHeight + 16
                radius: 8; color: root.bgInput; border.width: 1; border.color: descField.activeFocus ? root.clrAccent : root.clrBorder
                visible: root.isTracking
                QQC2.TextField {
                    id: descField; anchors.fill: parent; anchors.margins: 6
                    text: root.isTracking ? root.descriptionDraft : ""
                    placeholderText: i18n("Beschreibung…")
                    color: root.clrText; placeholderTextColor: root.clrTextMuted
                    background: Item {}
                    onEditingFinished: root.saveDescription(text)
                }
                Rectangle { visible: root.descriptionSavedFlash; anchors.centerIn: descField; width: 22; height: 22; radius: 11
                    color: Qt.rgba(root.clrAccent.r, root.clrAccent.g, root.clrAccent.b, 0.18)
                    border.width: 1; border.color: root.clrAccent
                    QQC2.Label { anchors.centerIn: parent; text: "✓"; font.pointSize: 11; color: root.clrAccent; font.bold: true }
                }
            }

            // ══════ NOT TRACKING MESSAGE ══════
            Rectangle {
                visible: !root.isTracking
                Layout.fillWidth: true; radius: 8
                height: notTrackLabel.implicitHeight + 20; color: root.bgSurface
                QQC2.Label {
                    id: notTrackLabel; anchors.centerIn: parent
                    text: !root.isConfigured ? i18n("Keine Aktivität. Verbinde Plasmai über das Menü mit Kimai.")
                          : root.pinnedEntries.length > 0 ? i18n("Keine Aktivität. Tippe auf einen Favoriten, um zu starten.")
                          : i18n("Keine Aktivität.")
                    color: root.clrTextMuted; font.pointSize: 12
                }
            }

                        // ══════ CONTINUE BUTTON ══════
            QQC2.Button {
                Layout.fillWidth: true
                visible: !root.isTracking && root.isConfigured && root.lastRecent
                enabled: !root.isBusy && root.connectionState !== "error"
                contentItem: RowLayout { spacing: 6
                    Canvas { Layout.preferredWidth: 14; Layout.preferredHeight: 12
                        onPaint: { var ctx = getContext("2d"); ctx.reset(); ctx.fillStyle = root.clrText; ctx.beginPath(); ctx.moveTo(2, 1); ctx.lineTo(12, 6); ctx.lineTo(2, 11); ctx.closePath(); ctx.fill() }
                    }
                    QQC2.Label { text: i18n("Continue · %1 · %2", KimaiApi.displayProjectName(root.lastRecent, root.projects), KimaiApi.displayActivityName(root.lastRecent, root.allActivities, root.activitiesByProject)); color: root.clrText; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true }
                }
                background: Rectangle { radius: 8; color: parent.down ? Qt.darker(root.clrAccent, 1.2) : (parent.hovered ? Qt.lighter(root.clrAccent, 1.1) : root.clrAccent) }
                onClicked: root.continueRecent(root.lastRecent)
            }

            // ══════ FAVORITES ══════
            QQC2.Label {
                Layout.fillWidth: true; Layout.topMargin: 4
                text: i18n("Favoriten"); font.bold: true; font.pointSize: 13; color: root.clrText
                visible: root.showFavorites && root.pinnedEntries.length > 0
            }
            Repeater {
                model: root.showFavorites ? root.pinnedEntries : []
                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    required property int index
                    property string pinKey: String(modelData.projectId || "") + "|" + String(modelData.activityId || "")
                    property bool isRunning: root.alreadyRunningHintKey === pinKey
                    Layout.fillWidth: true; implicitWidth: 1; topPadding: 6; bottomPadding: 6
                    contentItem: Item {
                        implicitHeight: 36
                        Row {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                            Rectangle { width: 6; height: 18; radius: 3; color: modelData.color || KimaiApi.DEFAULT_CUSTOMER_COLOR; border.width: 1; border.color: Qt.rgba(0,0,0,0.15); anchors.verticalCenter: parent.verticalCenter }
                            Canvas { width: 18; height: 14; anchors.verticalCenter: parent.verticalCenter
                                onPaint: { var ctx = getContext("2d"); ctx.reset(); ctx.fillStyle = root.clrAccent; ctx.beginPath(); ctx.moveTo(4, 1); ctx.lineTo(14, 7); ctx.lineTo(4, 13); ctx.closePath(); ctx.fill() }
                            }
                        }
                        ColumnLayout { anchors.left: parent.left; anchors.leftMargin: 34; anchors.right: rightZone.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                            QQC2.Label { text: modelData.projectName || ""; color: root.clrText; elide: Text.ElideRight; maximumLineCount: 1 }
                            QQC2.Label { text: modelData.activityName || ""; font.pointSize: 10; color: root.clrTextSec; elide: Text.ElideRight; maximumLineCount: 1 }
                        }
                        Item { id: rightZone; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: isRunning ? 80 : 32; height: 32
                            QQC2.Label { visible: isRunning; anchors.fill: parent; text: i18n("Already running.") + " " + KimaiApi.formatDurationShort(root.elapsedSeconds); color: root.clrAccent; font.pointSize: 10; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
                            QQC2.ToolButton { visible: !isRunning; anchors.fill: parent
                                contentItem: QQC2.Label { text: "✕"; font.pointSize: 11; color: root.clrTextMuted; horizontalAlignment: Text.AlignHCenter }
                                background: Rectangle { radius: 6; color: parent.hovered ? Qt.rgba(0.91, 0.30, 0.24, 0.12) : "transparent" }
                                onClicked: root.togglePin(modelData.projectId || "", modelData.activityId || "") }
                        }
                    }
                    background: Rectangle { radius: 6; color: parent.hovered ? Qt.rgba(1,1,1,0.05) : "transparent" }
                    onClicked: { if(root.isConfigured && !root.isBusy) root.requestRestartFromRecent({ project: modelData.projectId, activity: modelData.activityId }) }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true; visible: root.showFavorites && root.pinnedEntries.length === 0
                text: i18n("Tippe ☆ um einen Eintrag zu deinen Favoriten hinzuzufügen.")
                color: root.clrTextMuted; font.pointSize: 11; wrapMode: Text.WordWrap
            }

            // ══════ RECENT ══════
            QQC2.Label {
                Layout.fillWidth: true; Layout.topMargin: 4
                text: i18n("Zuletzt"); font.bold: true; font.pointSize: 13; color: root.clrText
                visible: root.showRecent && root.recentTimesheets.length > 0
            }
            Repeater {
                model: root.showRecent ? root.recentTimesheets : []
                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    required property int index
                    property string tsKey: root.switchHintKey(modelData)
                    property bool isRunning: root.alreadyRunningHintKey === tsKey
                    Layout.fillWidth: true; implicitWidth: 1; topPadding: 6; bottomPadding: 6
                    contentItem: Item {
                        implicitHeight: 36
                        Row {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                            Rectangle { width: 6; height: 18; radius: 3; color: KimaiApi.barColorInfoFromTimesheet(modelData, root.customersById).color || KimaiApi.DEFAULT_CUSTOMER_COLOR; border.width: 1; border.color: Qt.rgba(0,0,0,0.15); anchors.verticalCenter: parent.verticalCenter }
                            Canvas { width: 18; height: 14; anchors.verticalCenter: parent.verticalCenter
                                onPaint: { var ctx = getContext("2d"); ctx.reset(); ctx.fillStyle = root.clrAccent; ctx.beginPath(); ctx.moveTo(4, 1); ctx.lineTo(14, 7); ctx.lineTo(4, 13); ctx.closePath(); ctx.fill() }
                            }
                        }
                        ColumnLayout { anchors.left: parent.left; anchors.leftMargin: 34; anchors.right: rightZone2.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                            QQC2.Label { text: KimaiApi.displayActivityName(modelData, root.allActivities, root.activitiesByProject); color: root.clrText; elide: Text.ElideRight; maximumLineCount: 1 }
                            QQC2.Label {
                                text: { var bits = [KimaiApi.displayProjectName(modelData, root.projects)]; var secs = modelData.duration || 0; if (secs > 0) bits.push(KimaiApi.formatDurationShort(secs)); bits.push(root.formatRelativeTime(modelData.end || modelData.begin)); return bits.join(" · ") }
                                font.pointSize: 10; color: root.clrTextSec; elide: Text.ElideRight; maximumLineCount: 1 }
                        }
                        Item { id: rightZone2; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: isRunning ? 80 : 72; height: 32
                            QQC2.Label { visible: isRunning; anchors.fill: parent; text: i18n("Already running.") + " " + KimaiApi.formatDurationShort(root.elapsedSeconds); color: root.clrAccent; font.pointSize: 10; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
                            QQC2.ToolButton { visible: !isRunning; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32
                                contentItem: QQC2.Label { text: "☆"; font.pointSize: 14; color: root.clrTextSec; horizontalAlignment: Text.AlignHCenter }
                                background: Rectangle { radius: 6; color: parent.hovered ? Qt.rgba(1,1,1,0.08) : "transparent" }
                                onClicked: root.togglePin(modelData.project || "", modelData.activity || "") }
                            QQC2.ToolButton { visible: !isRunning; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32
                                contentItem: QQC2.Label { text: "⋮"; font.pointSize: 16; color: root.clrTextSec; horizontalAlignment: Text.AlignHCenter }
                                background: Rectangle { radius: 6; color: "transparent" }
                                onClicked: {
                                    recentContextMenu.index = index; recentContextMenu.ts = modelData
                                    var btn = parent
                                    var p = btn.mapToItem(page.contentItem, 0, btn.height + 4)
                                    recentContextMenu.x = Math.min(p.x, page.width - recentContextMenu.width - 16)
                                    recentContextMenu.y = Math.min(p.y, page.height - recentContextMenu.height - 16)
                                    recentContextMenu.open()
                                } }
                        }
                    }
                    background: Rectangle { radius: 6; color: parent.hovered ? Qt.rgba(1,1,1,0.05) : "transparent" }
                    onClicked: root.requestRestartFromRecent(modelData)
                }
            }

// ══════ BOTTOM SPACER ══════
            Item { Layout.fillHeight: true; Layout.minimumHeight: 12 }
        }
    } // Flickable

    // ══════ CONTEXT MENUS ══════
    QQC2.Menu {
        id: recentContextMenu
        property int index: -1
        property var ts: null
        QQC2.MenuItem { text: i18n("Edit"); onClicked: { if(recentContextMenu.ts) pageStack.push(manualPageComponent, { editTs: recentContextMenu.ts }) } }
        QQC2.MenuItem { text: i18n("Delete"); onClicked: { if(recentContextMenu.ts) { deleteDialog.target = recentContextMenu.ts; deleteDialog.open() } } }
    }

    // ══════ DIALOGS ══════
    QQC2.Dialog {
        id: confirmDialog; title: i18n("Tracking beenden?"); modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        width: Math.min(320, parent ? parent.width * 0.9 : 320)
        contentItem: QQC2.Label { text: i18n("%1 · %2 beenden?", root.currentProject, root.currentActivity); wrapMode: Text.WordWrap; color: root.clrText }
        onAccepted: root.stopTracking()
        background: Rectangle { radius: 12; color: root.bgDialog; border.width: 1; border.color: root.clrBorder }
    }
    QQC2.Dialog {
        id: deleteDialog; property var target: null
        title: i18n("Eintrag löschen?"); modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        width: Math.min(320, parent ? parent.width * 0.9 : 320)
        contentItem: QQC2.Label { text: i18n("Diesen Eintrag wirklich löschen?"); wrapMode: Text.WordWrap; color: root.clrText }
        onAccepted: { if(target) root.deleteEntry(target); target = null }
        background: Rectangle { radius: 12; color: root.bgDialog; border.width: 1; border.color: root.clrBorder }
    }
    QQC2.Dialog {
        id: switchDialog; modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        width: Math.min(320, parent ? parent.width * 0.9 : 320)
        contentItem: QQC2.Label {
            text: root.pendingSwitchTimesheet ? i18n("Zu %1 · %2 wechseln?", KimaiApi.displayProjectName(root.pendingSwitchTimesheet, root.projects), KimaiApi.displayActivityName(root.pendingSwitchTimesheet, root.allActivities, root.activitiesByProject)) : ""
            wrapMode: Text.WordWrap; color: root.clrText
        }
        onAccepted: {
            var ts = root.pendingSwitchTimesheet; root.pendingSwitchTimesheet = null
            if (ts) root.switchToActivity(KimaiApi.projectId(ts), KimaiApi.activityId(ts), KimaiApi.displayProjectName(ts, root.projects), KimaiApi.displayActivityName(ts, root.allActivities, root.activitiesByProject), ts.description || "")
        }
        onRejected: root.pendingSwitchTimesheet = null
        background: Rectangle { radius: 12; color: root.bgDialog; border.width: 1; border.color: root.clrBorder }
    }
}
