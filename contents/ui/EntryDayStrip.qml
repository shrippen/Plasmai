import QtQuick
import "../code/kimaiApi.js" as KimaiApi
import "../code/dateTimeFormat.js" as DTF
import "../code/solar.js" as Solar
import "Kante"

/**
 * Day strip (Kante): today's entries on a KanteDayStrip, each in its project
 * colour (a running entry in the accent), daylight from the location, the work
 * day as the work band, a "now" mark. The System style keeps the DaySparkline.
 * This file only turns Kimai timesheets into the strip's hours.
 */
KanteDayStrip {
    id: strip

    property var entries: []
    property var customersById: ({})
    property string workDayBegin: "09:00"
    property string workDayEnd: "18:00"
    /** Location for daylight (NaN: no daylight). */
    property real latitude: NaN
    property real longitude: NaN
    /** Bump to move the "now" mark (the widget's minute tick). */
    property int nowTick: 0

    /** Label every other hour: the strip usually spans a work day. */
    readonly property int labelStep: 2

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
        void nowTick // re-evaluate when the minute ticks
        return hoursOfDay(new Date())
    }

    // Sunrise and sunset in hours; invalid without a location.
    readonly property var sun: {
        void nowTick // re-evaluate when the minute ticks
        if (isNaN(latitude) || isNaN(longitude)) {
            return { valid: false }
        }
        return Solar.daySolarFractions(new Date(), latitude, longitude)
    }

    // Axis: the work day, widened to whole hours around entries and "now".
    readonly property var span: {
        var lo = workBegin
        var hi = Math.max(workEnd, nowHours)
        for (var i = 0; i < (entries || []).length; i++) {
            var b = DTF.parseStamp(entries[i].begin)
            if (!isNaN(b.getTime())) {
                lo = Math.min(lo, hoursOfDay(b))
            }
            var e = entries[i].end ? DTF.parseStamp(entries[i].end) : null
            if (e && !isNaN(e.getTime())) {
                hi = Math.max(hi, hoursOfDay(e))
            }
        }
        lo = Math.max(0, Math.floor(lo))
        hi = Math.min(24, Math.ceil(hi))
        return { lo: lo, hi: Math.max(lo + 1, hi) }
    }

    spanFrom: span.lo
    spanTo: span.hi
    tickStep: labelStep
    now: nowHours
    workFrom: workBegin
    workTo: workEnd
    sunrise: sun.valid ? sun.sunrise * 24 : -1
    sunset: sun.valid ? sun.sunset * 24 : -1

    // Entries as segments: {from, to, color}; a running entry has no colour (the accent).
    segments: {
        var out = []
        var list = entries || []
        for (var i = 0; i < list.length; i++) {
            var ts = list[i]
            var begin = DTF.parseStamp(ts.begin)
            if (isNaN(begin.getTime())) {
                continue
            }
            var end = ts.end ? DTF.parseStamp(ts.end) : null
            var segment = { from: hoursOfDay(begin), to: end ? hoursOfDay(end) : nowHours, kind: "work" }
            if (end) {
                segment.color = String(KimaiApi.barColorInfoFromTimesheet(ts, customersById).color)
            }
            out.push(segment)
        }
        return out
    }
}
