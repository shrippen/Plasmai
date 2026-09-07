import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/timeTracker.js" as TimeTracker
import "../contents/code/kimaiApi.js" as KimaiApi
import "../contents/code/statsData.js" as StatsData

Kirigami.Page {
    id: page
    title: ""
    background: Rectangle { color: root.bgWindow }
    property var timesheets: []; property bool loading: false; property string billableFilter: StatsData.BILLABLE_ALL
    property int dayOffset: 0; property int weekOffset: 0; property int hourWeekOffset: 0; property int pieWeekOffset: 0
    readonly property var nowDate: new Date()
    readonly property var selectedDay: StatsData.addDays(StatsData.startOfDay(nowDate), dayOffset)
    readonly property var selectedWeekStart: StatsData.addDays(StatsData.startOfWeek(nowDate), weekOffset * 7)
    readonly property var selectedHourWeekStart: StatsData.addDays(StatsData.startOfWeek(nowDate), hourWeekOffset * 7)
    readonly property var selectedPieWeekStart: StatsData.addDays(StatsData.startOfWeek(nowDate), pieWeekOffset * 7)
    readonly property var filteredTS: StatsData.filterBillable(timesheets, billableFilter)
    readonly property var hourlyModel: { var b = StatsData.hourlyBreakdown(filteredTS, selectedDay, Date.now()); var o = []; for (var i = 0; i < b.length; i++) o.push({ label: (i % 3 === 0) ? b[i].label : "", seconds: b[i].seconds, color: "#3584e4" }); return o; }
    readonly property var weeklyStacks: StatsData.weeklyProjectStacks(filteredTS, selectedWeekStart, root.customersById, Date.now(), 6)
    readonly property var weeklyDays: (weeklyStacks && weeklyStacks.days) ? weeklyStacks.days : []
    readonly property var weeklyLegend: (weeklyStacks && weeklyStacks.legend) ? weeklyStacks.legend : []
    readonly property var weekHourData: StatsData.weeklyHourTimeline(filteredTS, selectedHourWeekStart, root.customersById, Date.now(), 8, root.workDayBegin, root.workDayEnd)
    readonly property var weekHourDays: (weekHourData && weekHourData.days) ? weekHourData.days : []
    readonly property var weekHourLegend: (weekHourData && weekHourData.legend) ? weekHourData.legend : []
    readonly property real weekHourMin: (weekHourData && weekHourData.hourMin !== undefined) ? weekHourData.hourMin : 0
    readonly property real weekHourMax: (weekHourData && weekHourData.hourMax !== undefined) ? weekHourData.hourMax : 24
    readonly property var todayPie: { var d = StatsData.startOfDay(nowDate); return StatsData.activityBreakdown(filteredTS, d, StatsData.endOfDay(d), Date.now(), 6, root.customersById); }
    readonly property var todayPieRows: (todayPie && todayPie.rows) ? todayPie.rows : []
    readonly property int todayPieTotal: (todayPie && todayPie.totalSeconds) ? todayPie.totalSeconds : 0
    readonly property var weekPie: { var w = selectedPieWeekStart; return StatsData.activityBreakdown(filteredTS, w, StatsData.endOfWeek(w), Date.now(), 6, root.customersById); }
    readonly property var weekPieRows: (weekPie && weekPie.rows) ? weekPie.rows : []
    readonly property int weekPieTotal: (weekPie && weekPie.totalSeconds) ? weekPie.totalSeconds : 0
    readonly property real filteredTodaySeconds: StatsData.sumSecondsInRange(filteredTS, StatsData.startOfDay(nowDate), StatsData.endOfDay(nowDate), Date.now())
    readonly property real filteredWeekSeconds: StatsData.sumSecondsInRange(filteredTS, StatsData.startOfWeek(nowDate), StatsData.endOfWeek(nowDate), Date.now())
    function fmt(s) { return i18n("%1h %2m", Math.floor(s / 3600), Math.floor((s % 3600) / 60)) }
    function shiftDay(d) { dayOffset += d; loadForOffsets() }
    function shiftWeek(d) { weekOffset += d; loadForOffsets() }
    function shiftHourWeek(d) { hourWeekOffset += d; loadForOffsets() }
    function shiftPieWeek(d) { pieWeekOffset += d; loadForOffsets() }
    property var _rangeBeginMs: 0; property var _rangeEndMs: 0
    function loadForOffsets() {
        var b = selectedDay
        if (selectedWeekStart < b) b = selectedWeekStart
        if (selectedHourWeekStart < b) b = selectedHourWeekStart
        if (selectedPieWeekStart < b) b = selectedPieWeekStart
        var e = StatsData.endOfDay(selectedDay)
        var we = StatsData.endOfWeek(selectedWeekStart); if (we > e) e = we
        var hwe = StatsData.endOfWeek(selectedHourWeekStart); if (hwe > e) e = hwe
        var pwe = StatsData.endOfWeek(selectedPieWeekStart); if (pwe > e) e = pwe
        var tws = StatsData.startOfWeek(nowDate); if (tws < b) b = tws
        var twe = StatsData.endOfWeek(tws); if (twe > e) e = twe
        b = KimaiApi.startOfWeekMonday(b); e = KimaiApi.endOfWeekSunday(e)
        loadStats(b, e)
    }
    function loadStats(b, e) {
        if (!root.apiToken) return; loading = true
        var url = TimeTracker.resolveUrl(root.activeProfile)
        var bMs = b.getTime(), eMs = e.getTime()
        if (_rangeBeginMs && _rangeEndMs && bMs >= _rangeBeginMs && eMs <= _rangeEndMs && timesheets.length > 0) { loading = false; return }
        tracker.fetchTimesheetsRange(url, root.apiToken, b, e, function(r) {
            loading = false
            if (r.ok) { timesheets = KimaiApi.hydrateTimesheets(r.data || [], root.projects, page.activityCatalog(), root.activitiesByProject); _rangeBeginMs = b.getTime(); _rangeEndMs = e.getTime() }
        })
    }
    function activityCatalog() { var l = []; for (var i = 0; i < root.activities.length; i++) l.push(root.activities[i]); return l }
    Component.onCompleted: loadForOffsets()
    Flickable {
        anchors.fill: parent; contentHeight: col.implicitHeight + 32; clip: true; flickableDirection: Flickable.VerticalFlick
        ColumnLayout { id: col; width: parent.width - 32; x: 16; spacing: 12
            Kirigami.Heading { level: 1; text: i18n("Statistics"); color: root.clrText }
            RowLayout { Layout.fillWidth: true; spacing: 0
                Repeater {
                    model: [{ label: i18n("All"), value: StatsData.BILLABLE_ALL }, { label: i18n("Billable"), value: StatsData.BILLABLE_ONLY }, { label: i18n("Non-billable"), value: StatsData.BILLABLE_NONE }]
                    delegate: QQC2.ToolButton { Layout.fillWidth: true; Layout.preferredWidth: 1; text: modelData.label; checked: page.billableFilter === modelData.value
                        onClicked: { page.billableFilter = modelData.value; page.loadForOffsets() }
                        contentItem: QQC2.Label { text: modelData.label; font.pointSize: 11; color: page.billableFilter === modelData.value ? root.clrText : root.clrTextSec; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: page.billableFilter === modelData.value ? root.clrButton : "transparent"; border.width: 1; border.color: root.clrBorder; radius: 6 }
                    }
                }
            }
            GridLayout { Layout.fillWidth: true; columns: 2; columnSpacing: 12; rowSpacing: 4
                QQC2.Label { text: i18n("Today"); color: root.clrTextSec; font.pointSize: 12 }
                QQC2.Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: page.loading ? "\u2026" : page.fmt(page.filteredTodaySeconds); color: root.clrText; font.pointSize: 12; font.bold: true }
                QQC2.Label { text: i18n("This week"); color: root.clrTextSec; font.pointSize: 12 }
                QQC2.Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: page.loading ? "\u2026" : page.fmt(page.filteredWeekSeconds); color: root.clrText; font.pointSize: 12; font.bold: true }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.clrSeparator }
            Kirigami.Heading { level: 4; text: i18n("Time by hour"); color: root.clrText; Layout.fillWidth: true }
            RowLayout { Layout.fillWidth: true
                QQC2.ToolButton { Layout.preferredWidth: 36; onClicked: page.shiftDay(-1)
                    contentItem: QQC2.Label { text: "\u2039"; font.pointSize: 22; color: root.clrText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
                QQC2.Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: root.clrText; text: page.dayOffset === 0 ? i18n("Today") : page.dayOffset === -1 ? i18n("Yesterday") : StatsData.formatDayLabel(page.selectedDay) }
                QQC2.ToolButton { Layout.preferredWidth: 36; enabled: page.dayOffset < 0; onClicked: page.shiftDay(1)
                    contentItem: QQC2.Label { text: "\u203A"; font.pointSize: 22; color: page.dayOffset < 0 ? root.clrText : root.clrTextMuted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
            }
            Item { Layout.fillWidth: true; implicitHeight: 200
                readonly property var model: page.hourlyModel
                readonly property real maxSeconds: { var m = 0; for (var i = 0; i < (model || []).length; i++) m = Math.max(m, Number(model[i].seconds) || 0); return m }
                QQC2.Label { anchors.centerIn: parent; visible: parent.maxSeconds <= 0; opacity: 0.6; color: root.clrTextSec; text: i18n("No time logged this day") }
                Item { id: yL; anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 24; width: 48; visible: parent.maxSeconds > 0
                    QQC2.Label { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; horizontalAlignment: Text.AlignRight; font.pointSize: 9; opacity: 0.6; color: root.clrTextSec; text: KimaiApi.formatDurationShort(hB.maxVal) }
                    QQC2.Label { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; font.pointSize: 9; opacity: 0.6; color: root.clrTextSec; text: KimaiApi.formatDurationShort(Math.round(hB.maxVal / 2)) }
                    QQC2.Label { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; horizontalAlignment: Text.AlignRight; font.pointSize: 9; opacity: 0.6; color: root.clrTextSec; text: "0" }
                }
                Canvas { id: hB; anchors.left: yL.right; anchors.leftMargin: 4; anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 24
                    property var barModel: page.hourlyModel; property real maxVal: hB.parent.maxSeconds
                    onPaint: { var ctx = getContext("2d"); ctx.reset(); var w = width, h = height, n = (barModel || []).length; if (n <= 0 || maxVal <= 0) return; ctx.strokeStyle = Qt.rgba(1,1,1,0.1); ctx.lineWidth = 1; for (var g = 0; g <= 4; g++) { var gy = Math.round(h * g / 4) + 0.5; ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke() }; var bw = Math.max(2, (w - (n - 1) * 2) / n); for (var i = 0; i < n; i++) { var secs = barModel[i].seconds || 0; var bh = maxVal > 0 ? Math.max(secs > 0 ? 2 : 0, h * (secs / maxVal)) : 0; ctx.fillStyle = secs > 0 ? (barModel[i].color || "#3584e4") : Qt.rgba(1,1,1,0.15); ctx.beginPath(); ctx.roundedRect(i * (bw + 2), h - bh, bw, bh, 1, 1); ctx.fill() } }
                    Connections { target: page; function onHourlyModelChanged() { hB.requestPaint() } }
                    Component.onCompleted: requestPaint()
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.clrSeparator }
            Kirigami.Heading { level: 4; text: i18n("Projects by day"); color: root.clrText; Layout.fillWidth: true }
            RowLayout { Layout.fillWidth: true
                QQC2.ToolButton { Layout.preferredWidth: 36; onClicked: page.shiftWeek(-1)
                    contentItem: QQC2.Label { text: "\u2039"; font.pointSize: 22; color: root.clrText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
                QQC2.Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: root.clrText; text: page.weekOffset === 0 ? i18n("This week") : StatsData.formatWeekLabel(page.selectedWeekStart) }
                QQC2.ToolButton { Layout.preferredWidth: 36; enabled: page.weekOffset < 0; onClicked: page.shiftWeek(1)
                    contentItem: QQC2.Label { text: "\u203A"; font.pointSize: 22; color: page.weekOffset < 0 ? root.clrText : root.clrTextMuted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
            }
            Item { Layout.fillWidth: true; implicitHeight: 200
                readonly property var days: page.weeklyDays
                readonly property real maxSeconds: { var m = 0; for (var i = 0; i < (days || []).length; i++) m = Math.max(m, Number(days[i].totalSeconds) || 0); return m }
                QQC2.Label { anchors.centerIn: parent; visible: parent.maxSeconds <= 0; opacity: 0.6; color: root.clrTextSec; text: i18n("No time logged this week") }
                Item { id: sY; anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 24; width: 48; visible: parent.maxSeconds > 0
                    QQC2.Label { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; horizontalAlignment: Text.AlignRight; font.pointSize: 9; opacity: 0.6; color: root.clrTextSec; text: KimaiApi.formatDurationShort(sB.maxVal) }
                    QQC2.Label { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; font.pointSize: 9; opacity: 0.6; color: root.clrTextSec; text: KimaiApi.formatDurationShort(Math.round(sB.maxVal / 2)) }
                    QQC2.Label { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; horizontalAlignment: Text.AlignRight; font.pointSize: 9; opacity: 0.6; color: root.clrTextSec; text: "0" }
                }
                Canvas { id: sB; anchors.left: sY.right; anchors.leftMargin: 4; anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 24
                    property var dayData: page.weeklyDays; property real maxVal: sB.parent.maxSeconds
                    onPaint: { var ctx = getContext("2d"); ctx.reset(); var w = width, h = height, n = (dayData || []).length; if (n <= 0 || maxVal <= 0) return; ctx.strokeStyle = Qt.rgba(1,1,1,0.1); ctx.lineWidth = 1; for (var g = 0; g <= 4; g++) { var gy = Math.round(h * g / 4) + 0.5; ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke() }; var cw = Math.max(4, (w - (n - 1) * 8) / n); for (var d = 0; d < n; d++) { var day = dayData[d]; var stacks = day.stacks || []; var total = day.totalSeconds || 0; var cx = d * (cw + 8); var sy = h; for (var s = 0; s < stacks.length; s++) { var seg = stacks[s]; var sh = total > 0 ? Math.max(1, h * (seg.seconds / total)) : 0; sy -= sh; ctx.fillStyle = seg.color || "#999"; ctx.beginPath(); ctx.rect(cx, sy, cw, sh); ctx.fill() } }; ctx.fillStyle = Qt.rgba(1,1,1,0.7); ctx.font = "9px sans-serif"; ctx.textAlign = "center"; for (var d2 = 0; d2 < n; d2++) { var day2 = dayData[d2]; ctx.fillText(day2.label || "", d2 * (cw + 8) + cw / 2, h + 14) } }
                    Connections { target: page; function onWeeklyDaysChanged() { sB.requestPaint() } }
                    Component.onCompleted: requestPaint()
                }
            }
            GridLayout { Layout.fillWidth: true; columns: 2; columnSpacing: 12; rowSpacing: 4; visible: page.weeklyLegend.length > 0
                Repeater { model: page.weeklyLegend; delegate: RowLayout { spacing: 4; Layout.fillWidth: true
                    Rectangle { width: 10; height: 10; radius: 5; color: modelData.color || "#999"; Layout.alignment: Qt.AlignVCenter }
                    QQC2.Label { text: modelData.name || ""; font.pointSize: 10; color: root.clrTextSec; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                } }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.clrSeparator }
            Kirigami.Heading { level: 4; text: i18n("Projects by hour"); color: root.clrText; Layout.fillWidth: true }
            RowLayout { Layout.fillWidth: true
                QQC2.ToolButton { Layout.preferredWidth: 36; onClicked: page.shiftHourWeek(-1)
                    contentItem: QQC2.Label { text: "\u2039"; font.pointSize: 22; color: root.clrText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
                QQC2.Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: root.clrText; text: page.hourWeekOffset === 0 ? i18n("This week") : StatsData.formatWeekLabel(page.selectedHourWeekStart) }
                QQC2.ToolButton { Layout.preferredWidth: 36; enabled: page.hourWeekOffset < 0; onClicked: page.shiftHourWeek(1)
                    contentItem: QQC2.Label { text: "\u203A"; font.pointSize: 22; color: page.hourWeekOffset < 0 ? root.clrText : root.clrTextMuted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
            }
            ColumnLayout { id: tC; Layout.fillWidth: true; spacing: 2
                property var hourDays: page.weekHourDays; property real hMin: page.weekHourMin; property real hMax: page.weekHourMax; property real hSpan: Math.max(1, hMax - hMin)
                    QQC2.Label { Layout.fillWidth: true; visible: page.weekHourDays.length === 0; text: i18n("No time logged this week"); opacity: 0.6; color: root.clrTextSec; horizontalAlignment: Text.AlignHCenter; Layout.topMargin: 16 }
                    Repeater { model: page.weekHourDays
                        delegate: RowLayout { spacing: 4; Layout.fillWidth: true; property var day: modelData
                            QQC2.Label { Layout.preferredWidth: 52; Layout.maximumWidth: 52; text: day.label || ""; font.pointSize: 10; color: root.clrTextSec; elide: Text.ElideRight }
                            Item { Layout.fillWidth: true; implicitHeight: 20
                                Repeater { model: day.segments || []; delegate: Item { property var seg: modelData
                                    x: Math.max(0, parent.width * ((seg.startHour - tC.hMin) / tC.hSpan)); width: Math.max(2, parent.width * ((seg.endHour - seg.startHour) / tC.hSpan)); height: Math.max(8, parent.height * 0.72); anchors.verticalCenter: parent.verticalCenter
                                    Rectangle { anchors.fill: parent; radius: height / 2; color: seg.color || "#3584e4"; opacity: 0.92 }
                                }
                            }
                            QQC2.Label { Layout.preferredWidth: 36; Layout.maximumWidth: 36; horizontalAlignment: Text.AlignRight; text: day.totalSeconds > 0 ? KimaiApi.formatDurationShort(day.totalSeconds) : ""; font.pointSize: 9; color: root.clrTextSec; opacity: 0.7 }
                        }
                    }
                }
            GridLayout { Layout.fillWidth: true; columns: 2; columnSpacing: 12; rowSpacing: 4; visible: page.weekHourLegend.length > 0
                Repeater { model: page.weekHourLegend; delegate: RowLayout { spacing: 4; Layout.fillWidth: true
                    Rectangle { width: 10; height: 10; radius: 5; color: modelData.color || "#999"; Layout.alignment: Qt.AlignVCenter }
                    QQC2.Label { text: modelData.name || ""; font.pointSize: 10; color: root.clrTextSec; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                    QQC2.Label { text: KimaiApi.formatDurationShort(modelData.seconds || 0); font.pointSize: 10; font.bold: true; color: root.clrText; Layout.preferredWidth: 48; Layout.minimumWidth: 48; Layout.maximumWidth: 48; horizontalAlignment: Text.AlignRight }
                } }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.clrSeparator }
            Kirigami.Heading { level: 4; text: i18n("Activity distribution"); color: root.clrText; Layout.fillWidth: true }
            Kirigami.Heading { level: 5; text: i18n("Today"); color: root.clrTextSec; Layout.fillWidth: true }
            Rectangle { Layout.fillWidth: true; visible: page.todayPieTotal > 0; radius: 12; color: root.bgCard; border.width: 1; border.color: root.clrBorder; implicitHeight: tpC.implicitHeight + 32
                ColumnLayout { id: tpC; anchors.fill: parent; anchors.margins: 16; spacing: 12
                    Item { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 140; Layout.preferredHeight: 140
                        Canvas { id: tpCv; anchors.fill: parent; property var rows: page.todayPieRows; property real total: page.todayPieTotal
                            onPaint: { var ctx = getContext("2d"); ctx.reset(); var cx = width / 2, cy = height / 2, r = Math.min(cx, cy) - 4; if (total <= 0) return; var sa = -Math.PI / 2; for (var i = 0; i < rows.length; i++) { var sw = (rows[i].seconds / total) * 2 * Math.PI; ctx.beginPath(); ctx.moveTo(cx, cy); ctx.arc(cx, cy, r, sa, sa + sw); ctx.closePath(); ctx.fillStyle = rows[i].color; ctx.fill(); sa += sw }; ctx.beginPath(); ctx.arc(cx, cy, r * 0.45, 0, 2 * Math.PI); ctx.fillStyle = root.bgSurface; ctx.fill(); ctx.fillStyle = root.clrText; ctx.font = "bold 13px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(page.fmt(page.todayPieTotal), cx, cy) }
                            Connections { target: page; function onTodayPieRowsChanged() { tpCv.requestPaint() } }
                            Component.onCompleted: requestPaint()
                        }
                    }
                    Repeater { model: page.todayPieRows; delegate: RowLayout { Layout.fillWidth: true; spacing: 8
                        Rectangle { width: 10; height: 10; radius: 5; color: modelData.color; Layout.alignment: Qt.AlignVCenter }
                        QQC2.Label { text: modelData.name; color: root.clrText; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0; font.pointSize: 11 }
                        QQC2.Label { text: page.fmt(modelData.seconds); color: root.clrTextSec; font.pointSize: 11; font.family: "monospace"; Layout.preferredWidth: 56; Layout.minimumWidth: 56; Layout.maximumWidth: 56; horizontalAlignment: Text.AlignRight }
                    } }
                }
            }
            QQC2.Label { visible: page.todayPieTotal <= 0 && !page.loading; text: i18n("No activities today"); opacity: 0.6; color: root.clrTextSec; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; Layout.topMargin: 8; Layout.bottomMargin: 8 }
            Kirigami.Heading { level: 5; text: i18n("This week"); color: root.clrTextSec; Layout.fillWidth: true }
            RowLayout { Layout.fillWidth: true
                QQC2.ToolButton { Layout.preferredWidth: 36; onClicked: page.shiftPieWeek(-1)
                    contentItem: QQC2.Label { text: "\u2039"; font.pointSize: 22; color: root.clrText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
                QQC2.Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: root.clrText; text: page.pieWeekOffset === 0 ? i18n("This week") : StatsData.formatWeekLabel(page.selectedPieWeekStart) }
                QQC2.ToolButton { Layout.preferredWidth: 36; enabled: page.pieWeekOffset < 0; onClicked: page.shiftPieWeek(1)
                    contentItem: QQC2.Label { text: "\u203A"; font.pointSize: 22; color: page.pieWeekOffset < 0 ? root.clrText : root.clrTextMuted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
            }
            Rectangle { Layout.fillWidth: true; visible: page.weekPieTotal > 0; radius: 12; color: root.bgCard; border.width: 1; border.color: root.clrBorder; implicitHeight: wpC.implicitHeight + 32
                ColumnLayout { id: wpC; anchors.fill: parent; anchors.margins: 16; spacing: 12
                    Item { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 140; Layout.preferredHeight: 140
                        Canvas { id: wpCv; anchors.fill: parent; property var rows: page.weekPieRows; property real total: page.weekPieTotal
                            onPaint: { var ctx = getContext("2d"); ctx.reset(); var cx = width / 2, cy = height / 2, r = Math.min(cx, cy) - 4; if (total <= 0) return; var sa = -Math.PI / 2; for (var i = 0; i < rows.length; i++) { var sw = (rows[i].seconds / total) * 2 * Math.PI; ctx.beginPath(); ctx.moveTo(cx, cy); ctx.arc(cx, cy, r, sa, sa + sw); ctx.closePath(); ctx.fillStyle = rows[i].color; ctx.fill(); sa += sw }; ctx.beginPath(); ctx.arc(cx, cy, r * 0.45, 0, 2 * Math.PI); ctx.fillStyle = root.bgSurface; ctx.fill(); ctx.fillStyle = root.clrText; ctx.font = "bold 13px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(page.fmt(page.weekPieTotal), cx, cy) }
                            Connections { target: page; function onWeekPieRowsChanged() { wpCv.requestPaint() } }
                            Component.onCompleted: requestPaint()
                        }
                    }
                    Repeater { model: page.weekPieRows; delegate: RowLayout { Layout.fillWidth: true; spacing: 8
                        Rectangle { width: 10; height: 10; radius: 5; color: modelData.color; Layout.alignment: Qt.AlignVCenter }
                        QQC2.Label { text: modelData.name; color: root.clrText; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0; font.pointSize: 11 }
                        QQC2.Label { text: page.fmt(modelData.seconds); color: root.clrTextSec; font.pointSize: 11; font.family: "monospace"; Layout.preferredWidth: 56; Layout.minimumWidth: 56; Layout.maximumWidth: 56; horizontalAlignment: Text.AlignRight }
                    } }
                }
            }
            QQC2.Label { visible: page.weekPieTotal <= 0 && !page.loading; text: i18n("No activities this week"); opacity: 0.6; color: root.clrTextSec; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; Layout.topMargin: 8; Layout.bottomMargin: 8 }
            Item { Layout.fillHeight: true; Layout.minimumHeight: 32 }
        }
    }
}
}
