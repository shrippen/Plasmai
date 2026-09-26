import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import "../../contents/code/kimaiApi.js" as KimaiApi
import "."
import "../Kante"

/**
 * Kante day strip: today's entries as flat segments on one track, the work
 * day tinted, a thin "now" mark, hour labels below. The System style keeps
 * the DaySparkline instead.
 *
 *   06        10        14        18        22
 *   [##][###]       |[####]
 */
ColumnLayout {
    id: strip

    property var entries: []
    property var customersById: ({})
    property string workDayBegin: "09:00"
    property string workDayEnd: "18:00"
    /** Bump to move the "now" mark (the widget's minute tick). */
    property int nowTick: 0

    spacing: 2

    function hourOf(hhmm, fallback) {
        var parts = String(hhmm || "").split(":")
        var h = parseInt(parts[0], 10)
        var m = parseInt(parts[1] || "0", 10)
        return isNaN(h) ? fallback : h + (isNaN(m) ? 0 : m / 60)
    }

    function hoursOfDay(date) {
        return date.getHours() + date.getMinutes() / 60 + date.getSeconds() / 3600
    }

    readonly property real workBegin: hourOf(workDayBegin, 9)
    readonly property real workEnd: hourOf(workDayEnd, 18)
    readonly property real nowHours: {
        nowTick
        return hoursOfDay(new Date())
    }

    // Axis: the work day, widened to whole hours around entries and "now".
    readonly property var span: {
        var lo = workBegin
        var hi = Math.max(workEnd, nowHours)
        for (var i = 0; i < (entries || []).length; i++) {
            var b = new Date(entries[i].begin)
            if (!isNaN(b.getTime())) {
                lo = Math.min(lo, hoursOfDay(b))
            }
            var e = entries[i].end ? new Date(entries[i].end) : null
            if (e && !isNaN(e.getTime())) {
                hi = Math.max(hi, hoursOfDay(e))
            }
        }
        lo = Math.max(0, Math.floor(lo))
        hi = Math.min(24, Math.ceil(hi))
        return { lo: lo, hi: Math.max(lo + 1, hi) }
    }

    function xOf(hours) {
        return (hours - span.lo) / (span.hi - span.lo) * track.width
    }

    Rectangle {
        id: track
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit * 0.55)
        color: KanteStyle.sunkenColor

        Rectangle {
            x: strip.xOf(strip.workBegin)
            width: Math.max(0, strip.xOf(strip.workEnd) - x)
            height: parent.height
            color: KanteStyle.tint(KanteStyle.textColor, 0.06)
        }

        Repeater {
            model: strip.entries || []
            delegate: Rectangle {
                readonly property var ts: modelData
                readonly property var begin: new Date(ts.begin)
                readonly property var end: ts.end ? new Date(ts.end) : new Date()
                x: strip.xOf(strip.hoursOfDay(begin))
                width: Math.max(2, strip.xOf(strip.hoursOfDay(end)) - x)
                height: parent.height
                color: ts.end ? KimaiApi.barColorInfoFromTimesheet(ts, strip.customersById).color : KanteStyle.accentColor
            }
        }

        Rectangle {
            x: strip.xOf(strip.nowHours)
            y: -2
            width: 1
            height: parent.height + 4
            color: KanteStyle.textColor
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: tickMetrics.height

        Repeater {
            model: Math.floor((strip.span.hi - strip.span.lo) / 2) + 1
            delegate: QQC2.Label {
                readonly property int hour: strip.span.lo + index * 2
                x: Math.min(strip.width - width, Math.max(0, strip.xOf(hour) - width / 2))
                text: (hour < 10 ? "0" : "") + hour
                font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize * 0.85, false)
                color: KanteStyle.mutedTextColor
            }
        }

        TextMetrics {
            id: tickMetrics
            font: KanteStyle.monoFont(KanteStyle.smallFont.pointSize * 0.85, false)
            text: "00"
        }
    }
}
