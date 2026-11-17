.pragma library
.import "./entityNames.js" as Names
.import "./dateTimeFormat.js" as DTF

/** The parts of an entry's texts that need no translation; EntryTexts.qml words them. */

var SECONDS_PER_MINUTE = 60
var MINUTES_PER_HOUR = 60
var HOURS_PER_DAY = 24
var DAYS_PER_WEEK = 7
/** Locale.ShortFormat; the enum is not visible in a JS library. */
var SHORT_FORMAT = 1

var Age = { None: "none", Now: "now", Minutes: "minutes", Hours: "hours", Yesterday: "yesterday", Days: "days", Date: "date" }

/** "Project · Activity · 13.08.26 10:00": what an entry is, for a link or a row. */
function summary(ts, catalog) {
    if (!ts) {
        return ""
    }
    var bits = [Names.displayProjectName(ts, catalog.projects),
                Names.displayActivityName(ts, catalog.activities, catalog.activitiesByProject)]
    var begin = DTF.parseStamp(ts.begin)
    if (!isNaN(begin.getTime())) {
        bits.push(begin.toLocaleDateString(Qt.locale(), SHORT_FORMAT) + " "
                  + begin.toLocaleTimeString(Qt.locale(), SHORT_FORMAT))
    }
    return bits.filter(function(b) { return !!b }).join(" · ")
}

/** How long before nowMs the stamp lies: { kind: Age.*, n } (n in the unit of the kind). */
function age(isoDate, nowMs) {
    if (!isoDate) {
        return { kind: Age.None, n: 0 }
    }
    var date = DTF.parseStamp(isoDate)
    if (isNaN(date.getTime())) {
        return { kind: Age.None, n: 0 }
    }
    var seconds = Math.floor((nowMs - date.getTime()) / 1000)
    if (seconds < SECONDS_PER_MINUTE) {
        return { kind: Age.Now, n: 0 }
    }
    var minutes = Math.floor(seconds / SECONDS_PER_MINUTE)
    if (minutes < MINUTES_PER_HOUR) {
        return { kind: Age.Minutes, n: minutes }
    }
    var hours = Math.floor(minutes / MINUTES_PER_HOUR)
    if (hours < HOURS_PER_DAY) {
        return { kind: Age.Hours, n: hours }
    }
    var days = Math.floor(hours / HOURS_PER_DAY)
    if (days === 1) {
        return { kind: Age.Yesterday, n: 1 }
    }
    if (days < DAYS_PER_WEEK) {
        return { kind: Age.Days, n: days }
    }
    return { kind: Age.Date, n: 0 }
}
