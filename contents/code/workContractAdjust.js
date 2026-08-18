.pragma library

/**
 * Adjust weekly work targets using kimai-holiday-bundle absences and public holidays.
 * Matches REDUCE semantics for vacation/sickness on contracted work days.
 */

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

function dateKey(date) {
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function parseIsoDate(text) {
    if (!text) {
        return null
    }
    var parts = String(text).substring(0, 10).split("-")
    if (parts.length !== 3) {
        return null
    }
    var y = parseInt(parts[0], 10)
    var m = parseInt(parts[1], 10) - 1
    var d = parseInt(parts[2], 10)
    if (isNaN(y) || isNaN(m) || isNaN(d)) {
        return null
    }
    return new Date(y, m, d)
}

function isApprovedAbsence(absence) {
    if (!absence) {
        return false
    }
    var status = String(absence.status || "").toLowerCase()
    if (status === "approved") {
        return true
    }
    // Sickness entries are effective without an approval step in the bundle.
    var type = String(absence.type || "").toLowerCase()
    return type === "sickness" || type === "sickness_relative"
}

function absenceReducesExpected(absence) {
    var type = String(absence && absence.type || "").toLowerCase()
    return type === "vacation"
        || type === "sickness"
        || type === "sickness_relative"
        || type === "other"
}

function absenceCoversDate(absence, date) {
    if (!isApprovedAbsence(absence) || !absenceReducesExpected(absence)) {
        return false
    }
    var start = parseIsoDate(absence.startDate)
    var end = parseIsoDate(absence.endDate || absence.startDate)
    if (!start || !end) {
        return false
    }
    var day = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    var from = new Date(start.getFullYear(), start.getMonth(), start.getDate())
    var to = new Date(end.getFullYear(), end.getMonth(), end.getDate())
    return day.getTime() >= from.getTime() && day.getTime() <= to.getTime()
}

function publicHolidayForDate(publicHolidays, date) {
    var key = dateKey(date)
    for (var i = 0; i < (publicHolidays || []).length; i++) {
        var ph = publicHolidays[i]
        if (ph && String(ph.date || "").substring(0, 10) === key) {
            return ph
        }
    }
    return null
}

/** Sum contracted seconds Mon–Sun minus vacation/holidays on work days. */
function effectiveWeekTargetSeconds(prefs, weekAnchorDate, absences, publicHolidays, daySecondsFn) {
    if (!prefs || typeof daySecondsFn !== "function") {
        return 0
    }
    var start = new Date(weekAnchorDate.getFullYear(), weekAnchorDate.getMonth(), weekAnchorDate.getDate())
    var day = start.getDay()
    var offset = day === 0 ? 6 : day - 1
    start.setDate(start.getDate() - offset)

    var total = 0
    var i
    for (i = 0; i < 7; i++) {
        var current = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
        var baseExpected = daySecondsFn(prefs, current)
        if (baseExpected <= 0) {
            continue
        }
        var covering = null
        for (var a = 0; a < (absences || []).length; a++) {
            var absence = absences[a]
            if (absenceCoversDate(absence, current)) {
                covering = absence
                break
            }
        }
        var ph = publicHolidayForDate(publicHolidays, current)
        var reduce = 0
        if (covering) {
            reduce = covering.halfDay ? Math.floor(baseExpected / 2) : baseExpected
        }
        if (ph) {
            var phReduce = ph.halfDay ? Math.floor(baseExpected / 2) : baseExpected
            reduce = Math.max(reduce, phReduce)
        }
        total += Math.max(0, baseExpected - reduce)
    }
    return total
}
