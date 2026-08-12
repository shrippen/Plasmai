import "../code/kimaiApi.js" as KimaiApi
import "../code/statsData.js" as StatsData
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

/**
 * Statistics pane — hourly bars, weekly project stacks, week hour timeline,
 * activity pies, with billable filter and day/week switchers.
 */
ColumnLayout {
    id: root

    property var timesheets: []
    property var customersById: ({
    })
    property int todayTargetSeconds: 0
    property int weekTargetSeconds: 0
    property bool hasWorkContract: false
    property string workDayBegin: KimaiApi.DEFAULT_WORK_DAY_BEGIN
    property string workDayEnd: KimaiApi.DEFAULT_WORK_DAY_END
    //* "all" | "billable" | "nonbillable"
    property string billableFilter: StatsData.BILLABLE_ALL
    //* 0 = today; negative = past days
    property int dayOffset: 0
    //* 0 = current week; negative = past weeks — Projects by day
    property int weekOffset: 0
    //* 0 = current week; negative = past weeks — Projects by hour
    property int hourWeekOffset: 0
    //* 0 = current week; negative = past weeks — Activity distribution
    property int pieWeekOffset: 0
    /** Hide billable segmented control when the provider has no billable flag. */
    property bool supportsBillableFilter: true
    readonly property var nowDate: new Date()
    readonly property var selectedDay: StatsData.addDays(StatsData.startOfDay(nowDate), dayOffset)
    readonly property var selectedWeekStart: StatsData.addDays(StatsData.startOfWeek(nowDate), weekOffset * 7)
    readonly property var selectedHourWeekStart: StatsData.addDays(StatsData.startOfWeek(nowDate), hourWeekOffset * 7)
    readonly property var selectedPieWeekStart: StatsData.addDays(StatsData.startOfWeek(nowDate), pieWeekOffset * 7)
    readonly property var filteredTimesheets: StatsData.filterBillable(timesheets, billableFilter)
    readonly property string filterAllLabel: i18n("All")
    readonly property string filterBillableLabel: i18n("Billable")
    readonly property string filterNonBillableLabel: i18n("Non-billable")
    //* Shared width for all three filters = longest label (+ padding).
    readonly property real filterButtonWidth: Math.max(filterAllMetrics.advanceWidth, filterBillableMetrics.advanceWidth, filterNonBillableMetrics.advanceWidth) + Kirigami.Units.largeSpacing * 2
    readonly property var hourlyModel: {
        var buckets = StatsData.hourlyBreakdown(filteredTimesheets, selectedDay, Date.now());
        var out = [];
        for (var i = 0; i < buckets.length; i++) {
            out.push({
                "label": (i % 3 === 0) ? buckets[i].label : "",
                "seconds": buckets[i].seconds,
                "color": "#3584e4"
            });
        }
        return out;
    }
    readonly property var weeklyStacks: StatsData.weeklyProjectStacks(filteredTimesheets, selectedWeekStart, customersById, Date.now(), 6)
    readonly property var weeklyDays: (weeklyStacks && weeklyStacks.days) ? weeklyStacks.days : []
    readonly property var weeklyLegend: (weeklyStacks && weeklyStacks.legend) ? weeklyStacks.legend : []
    readonly property var weekHourData: StatsData.weeklyHourTimeline(filteredTimesheets, selectedHourWeekStart, customersById, Date.now(), 8, workDayBegin, workDayEnd)
    readonly property var weekHourDays: (weekHourData && weekHourData.days) ? weekHourData.days : []
    readonly property var weekHourLegend: (weekHourData && weekHourData.legend) ? weekHourData.legend : []
    readonly property real weekHourMin: (weekHourData && weekHourData.hourMin !== undefined) ? weekHourData.hourMin : 0
    readonly property real weekHourMax: (weekHourData && weekHourData.hourMax !== undefined) ? weekHourData.hourMax : 24
    readonly property var todayPie: {
        var day = StatsData.startOfDay(nowDate);
        return StatsData.activityBreakdown(filteredTimesheets, day, StatsData.endOfDay(day), Date.now(), 6, customersById);
    }
    readonly property var weekPie: {
        var ws = root.selectedPieWeekStart;
        return StatsData.activityBreakdown(filteredTimesheets, ws, StatsData.endOfWeek(ws), Date.now(), 6, customersById);
    }
    readonly property var todayPieRows: (todayPie && todayPie.rows) ? todayPie.rows : []
    readonly property int todayPieTotal: (todayPie && todayPie.totalSeconds) ? todayPie.totalSeconds : 0
    readonly property var weekPieRows: (weekPie && weekPie.rows) ? weekPie.rows : []
    readonly property int weekPieTotal: (weekPie && weekPie.totalSeconds) ? weekPie.totalSeconds : 0
    readonly property int filteredTodaySeconds: StatsData.sumSecondsInRange(filteredTimesheets, StatsData.startOfDay(nowDate), StatsData.endOfDay(nowDate), Date.now())
    readonly property int filteredWeekSeconds: StatsData.sumSecondsInRange(filteredTimesheets, StatsData.startOfWeek(nowDate), StatsData.endOfWeek(nowDate), Date.now())

    signal backRequested()
    signal needMoreHistory(date rangeBegin, date rangeEnd)

    function shiftDay(delta) {
        dayOffset += delta;
        requestRangeForOffsets();
    }

    function shiftWeek(delta) {
        weekOffset += delta;
        requestRangeForOffsets();
    }

    function shiftHourWeek(delta) {
        hourWeekOffset += delta;
        requestRangeForOffsets();
    }

    function shiftPieWeek(delta) {
        pieWeekOffset += delta;
        requestRangeForOffsets();
    }

    function requestRangeFor(day, weekBegin, hourWeekBegin, pieWeekBegin) {
        var weekEnd = StatsData.endOfWeek(weekBegin);
        var hourWeekEnd = StatsData.endOfWeek(hourWeekBegin);
        var pieWeekEnd = StatsData.endOfWeek(pieWeekBegin);
        var begin = StatsData.startOfDay(day);
        var end = StatsData.endOfDay(day);
        if (weekBegin < begin)
            begin = weekBegin;

        if (weekEnd > end)
            end = weekEnd;

        if (hourWeekBegin < begin)
            begin = hourWeekBegin;

        if (hourWeekEnd > end)
            end = hourWeekEnd;

        if (pieWeekBegin < begin)
            begin = pieWeekBegin;

        if (pieWeekEnd > end)
            end = pieWeekEnd;

        var todayWeekBegin = StatsData.startOfWeek(new Date());
        var todayWeekEnd = StatsData.endOfWeek(todayWeekBegin);
        if (todayWeekBegin < begin)
            begin = todayWeekBegin;

        if (todayWeekEnd > end)
            end = todayWeekEnd;

        root.needMoreHistory(begin, end);
    }

    function requestRangeForOffsets() {
        requestRangeFor(selectedDay, selectedWeekStart, selectedHourWeekStart, selectedPieWeekStart);
    }

    function ensureRangeForOffsets() {
        requestRangeForOffsets();
    }

    Component.onCompleted: ensureRangeForOffsets()

    TextMetrics {
        id: filterAllMetrics

        font: Kirigami.Theme.defaultFont
        text: root.filterAllLabel
    }

    TextMetrics {
        id: filterBillableMetrics

        font: Kirigami.Theme.defaultFont
        text: root.filterBillableLabel
    }

    TextMetrics {
        id: filterNonBillableMetrics

        font: Kirigami.Theme.defaultFont
        text: root.filterNonBillableLabel
    }

    // —— Billable filter (equal-width segmented toggle) ——
    // Centered Row with equal widths from the longest label. Cap to available
    // width (with a small inset) so checked borders are not clipped at the edges,
    // without inflating the scroll content width.
    Item {
        id: filterBar
        Layout.fillWidth: true
        Layout.preferredHeight: filterButtonRow.implicitHeight
        visible: root.supportsBillableFilter

        readonly property real sideInset: Kirigami.Units.smallSpacing
        readonly property real buttonWidth: {
            var avail = Math.max(0, width - sideInset * 2)
            var natural = root.filterButtonWidth
            if (natural * 3 <= avail) {
                return natural
            }
            return avail / 3
        }

        Row {
            id: filterButtonRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            PlasmaComponents3.ToolButton {
                width: filterBar.buttonWidth
                checkable: true
                autoExclusive: true
                checked: root.billableFilter === StatsData.BILLABLE_ALL
                text: root.filterAllLabel
                onClicked: root.billableFilter = StatsData.BILLABLE_ALL
            }
            PlasmaComponents3.ToolButton {
                width: filterBar.buttonWidth
                checkable: true
                autoExclusive: true
                checked: root.billableFilter === StatsData.BILLABLE_ONLY
                text: root.filterBillableLabel
                onClicked: root.billableFilter = StatsData.BILLABLE_ONLY
            }
            PlasmaComponents3.ToolButton {
                width: filterBar.buttonWidth
                checkable: true
                autoExclusive: true
                checked: root.billableFilter === StatsData.BILLABLE_NONE
                text: root.filterNonBillableLabel
                onClicked: root.billableFilter = StatsData.BILLABLE_NONE
            }
        }
    }

    // —— Summary ——
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            text: i18n("Today")
            opacity: 0.7
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            font.bold: true
            text: KimaiApi.formatDurationShort(root.filteredTodaySeconds)
        }

        PlasmaComponents3.Label {
            text: i18n("This week")
            opacity: 0.7
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            font.bold: true
            text: KimaiApi.formatDurationShort(root.filteredWeekSeconds)
        }

    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    // —— Hourly bars + day switcher ——
    PlasmaExtras.Heading {
        Layout.fillWidth: true
        level: 4
        text: i18n("Time by hour")
    }

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents3.ToolButton {
            icon.name: "go-previous"
            onClicked: root.shiftDay(-1)
            PlasmaComponents3.ToolTip.text: i18n("Previous day")
            PlasmaComponents3.ToolTip.visible: hovered
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.bold: true
            text: {
                if (root.dayOffset === 0)
                    return i18n("Today");

                if (root.dayOffset === -1)
                    return i18n("Yesterday");

                return StatsData.formatDayLabel(root.selectedDay);
            }
        }

        PlasmaComponents3.ToolButton {
            icon.name: "go-next"
            enabled: root.dayOffset < 0
            onClicked: root.shiftDay(1)
            PlasmaComponents3.ToolTip.text: i18n("Next day")
            PlasmaComponents3.ToolTip.visible: hovered
        }

    }

    BarChart {
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 7
        model: root.hourlyModel
        emptyText: i18n("No time logged this day")
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    // —— Weekly project stacks + week switcher ——
    PlasmaExtras.Heading {
        Layout.fillWidth: true
        level: 4
        text: i18n("Projects by day")
    }

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents3.ToolButton {
            icon.name: "go-previous"
            onClicked: root.shiftWeek(-1)
            PlasmaComponents3.ToolTip.text: i18n("Previous week")
            PlasmaComponents3.ToolTip.visible: hovered
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.bold: true
            text: {
                if (root.weekOffset === 0)
                    return i18n("This week");

                return StatsData.formatWeekLabel(root.selectedWeekStart);
            }
        }

        PlasmaComponents3.ToolButton {
            icon.name: "go-next"
            enabled: root.weekOffset < 0
            onClicked: root.shiftWeek(1)
            PlasmaComponents3.ToolTip.text: i18n("Next week")
            PlasmaComponents3.ToolTip.visible: hovered
        }

    }

    StackedBarChart {
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 7
        days: root.weeklyDays
        emptyText: i18n("No time logged this week")
    }

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing * 2
        visible: root.weeklyLegend.length > 0

        Repeater {
            model: root.weeklyLegend

            delegate: Row {
                spacing: 4

                CustomerColorDot {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 14
                    customerColor: modelData.color || KimaiApi.DEFAULT_CUSTOMER_COLOR
                    sizeFactor: 0.55
                    slotSizeFactor: 0.7
                }

                PlasmaComponents3.Label {
                    text: modelData.name || ""
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.8
                }

            }

        }

    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    // —— Projects by hour (week timeline) ——
    PlasmaExtras.Heading {
        Layout.fillWidth: true
        level: 4
        text: i18n("Projects by hour")
    }

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents3.ToolButton {
            icon.name: "go-previous"
            onClicked: root.shiftHourWeek(-1)
            PlasmaComponents3.ToolTip.text: i18n("Previous week")
            PlasmaComponents3.ToolTip.visible: hovered
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.bold: true
            text: {
                if (root.hourWeekOffset === 0)
                    return i18n("This week");

                return StatsData.formatWeekLabel(root.selectedHourWeekStart);
            }
        }

        PlasmaComponents3.ToolButton {
            icon.name: "go-next"
            enabled: root.hourWeekOffset < 0
            onClicked: root.shiftHourWeek(1)
            PlasmaComponents3.ToolTip.text: i18n("Next week")
            PlasmaComponents3.ToolTip.visible: hovered
        }

    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.7
        text: {
            var bits = [];
            if (root.weekHourData && root.weekHourData.weekendIncluded)
                bits.push(i18n("Weekdays and weekend — segments placed by clock time."));
            else
                bits.push(i18n("Weekdays — segments placed by clock time. Weekend appears when tracked."));
            bits.push(i18n("Axis shows business hours (%1–%2); expands if work falls outside.", root.workDayBegin, root.workDayEnd));
            return bits.join(" ");
        }
    }

    WeeklyHourChart {
        Layout.fillWidth: true
        days: root.weekHourDays
        hourMin: root.weekHourMin
        hourMax: root.weekHourMax
        emptyText: i18n("No time logged this week")
    }

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing * 2
        visible: root.weekHourLegend.length > 0

        Repeater {
            model: root.weekHourLegend

            delegate: Row {
                spacing: 4

                CustomerColorDot {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 14
                    customerColor: modelData.color || KimaiApi.DEFAULT_CUSTOMER_COLOR
                    sizeFactor: 0.55
                    slotSizeFactor: 0.7
                }

                PlasmaComponents3.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name || ""
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.8
                }

                PlasmaComponents3.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: KimaiApi.formatDurationShort(modelData.seconds || 0)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.bold: true
                    opacity: 0.9
                }

            }

        }

    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    // —— Activity pies ——
    PlasmaExtras.Heading {
        Layout.fillWidth: true
        level: 4
        text: i18n("Activity distribution")
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width > Kirigami.Units.gridUnit * 18 ? 2 : 1
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.largeSpacing

        PieChart {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
            title: i18n("Today")
            rows: root.todayPieRows
            totalSeconds: root.todayPieTotal
            emptyText: i18n("No activities today")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents3.ToolButton {
                    icon.name: "go-previous"
                    onClicked: root.shiftPieWeek(-1)
                    PlasmaComponents3.ToolTip.text: i18n("Previous week")
                    PlasmaComponents3.ToolTip.visible: hovered
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.bold: true
                    text: {
                        if (root.pieWeekOffset === 0)
                            return i18n("This week");

                        return StatsData.formatWeekLabel(root.selectedPieWeekStart);
                    }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "go-next"
                    enabled: root.pieWeekOffset < 0
                    onClicked: root.shiftPieWeek(1)
                    PlasmaComponents3.ToolTip.text: i18n("Next week")
                    PlasmaComponents3.ToolTip.visible: hovered
                }
            }

            PieChart {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                title: ""
                rows: root.weekPieRows
                totalSeconds: root.weekPieTotal
                emptyText: i18n("No activities this week")
            }
        }

    }

}
