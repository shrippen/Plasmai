.pragma library
.import "./kimaiApi.js" as KimaiApi
.import "./statsData.js" as StatsData
.import "./dateTimeFormat.js" as DTF

/**
 * Entries as a day and as a week, for the layouts (ROADMAP "Layouts"):
 * the day band, the ring and the gap prompt read blocks() and gaps(), the
 * timesheet grid reads weekGrid(). No requests, no Qt types: the TUI loads
 * this file too.
 *
 *   entries (Kimai-shaped, from fetchTimesheetsRange)
 *     ├─ blocks(entries, day, nowMs)   → [{ fromHour, toHour, running, … }]
 *     │    └─ gaps(blocks, from, to, minMinutes) → [{ fromHour, toHour, minutes }]
 *     └─ weekGrid(entries, weekStart, nowMs) → { rows, dayTotals, total }
 *
 * Hours are local wall-clock hours of the day, 0–24: a night shift from
 * 22:00 to 03:13 is 22–24 on its first day and 0–3.22 on the next.
 */

const DAYS_PER_WEEK = 7

/** Where a block was cut at midnight. */
var Cut = {
    NONE: "none",
    BEFORE: "before",
    AFTER: "after",
    BOTH: "both"
}

/** Local wall-clock hour of a Date on its day; the next midnight is 24. */
function clockHour(date, nextDay) {
    if (date.getTime() >= nextDay.getTime()) {
        return 24
    }
    return date.getHours() + date.getMinutes() / 60 + date.getSeconds() / 3600
}

function cutOf(before, after) {
    if (before && after) {
        return Cut.BOTH
    }
    if (before) {
        return Cut.BEFORE
    }
    return after ? Cut.AFTER : Cut.NONE
}

/**
 * The part of each entry that falls on `day`, oldest first. A running entry
 * (no end) lasts until nowMs.
 * Example: 08:15–12:30 → { fromHour: 8.25, toHour: 12.5, cut: NONE }.
 */
function blocks(entries, day, nowMs) {
    const dayStart = KimaiApi.startOfLocalDay(day)
    const nextDay = new Date(dayStart.getFullYear(), dayStart.getMonth(), dayStart.getDate() + 1)
    const out = []

    for (let i = 0; i < (entries || []).length; i++) {
        const entry = entries[i]
        const beginMs = DTF.stampMs(entry && entry.begin)
        if (isNaN(beginMs)) {
            continue
        }
        const running = !entry.end
        const endMs = running ? nowMs : DTF.stampMs(entry.end)
        if (isNaN(endMs)) {
            continue
        }

        // Only the part on this day.
        const fromMs = Math.max(beginMs, dayStart.getTime())
        const toMs = Math.min(endMs, nextDay.getTime())
        if (toMs <= fromMs) {
            continue
        }

        out.push({
            entry: entry,
            fromMs: fromMs,
            toMs: toMs,
            fromHour: clockHour(new Date(fromMs), nextDay),
            toHour: clockHour(new Date(toMs), nextDay),
            running: running,
            cut: cutOf(beginMs < dayStart.getTime(), endMs > nextDay.getTime())
        })
    }

    out.sort(function(a, b) { return a.fromMs - b.fromMs })
    return out
}

/**
 * Untracked spans between fromHour and toHour of at least minMinutes, from
 * sorted blocks(). Overlapping blocks count once.
 * Example: blocks 8–12.5 and 13.25–14, window 8–14, min 15 → [12.5–13.25, 45 min].
 */
function gaps(dayBlocks, fromHour, toHour, minMinutes) {
    const out = []
    let cursor = fromHour

    const push = function(until) {
        const end = Math.min(until, toHour)
        const minutes = Math.round((end - cursor) * 60)
        if (minutes >= minMinutes && minutes > 0) {
            out.push({ fromHour: cursor, toHour: end, minutes: minutes })
        }
    }

    for (let i = 0; i < (dayBlocks || []).length; i++) {
        const b = dayBlocks[i]
        if (cursor >= toHour) {
            break
        }
        if (b.fromHour > cursor) {
            push(b.fromHour)
        }
        cursor = Math.max(cursor, b.toHour)
    }

    if (cursor < toHour) {
        push(toHour)
    }
    return out
}

/** Row key of an entry: project and activity, as Kimai books them. */
function rowKey(entry) {
    return String(KimaiApi.projectId(entry) || 0) + "/" + String(KimaiApi.activityId(entry) || 0)
}

/**
 * Seconds per project and activity and weekday, Monday first.
 * rows: [{ key, project, activity, days: [7 × seconds], total, running }],
 * biggest total first; dayTotals: [7 × seconds]; total: seconds.
 */
function weekGrid(entries, weekStart, nowMs) {
    const monday = StatsData.startOfWeek(weekStart)
    const byKey = {}
    const rows = []
    const dayTotals = [0, 0, 0, 0, 0, 0, 0]
    let total = 0

    for (let i = 0; i < (entries || []).length; i++) {
        const entry = entries[i]
        const key = rowKey(entry)
        let row = byKey[key]

        for (let d = 0; d < DAYS_PER_WEEK; d++) {
            const day = StatsData.addDays(monday, d)
            const secs = StatsData.overlapSeconds(entry, StatsData.startOfDay(day),
                                                  StatsData.endOfDay(day), nowMs)
            if (secs <= 0) {
                continue
            }

            // First second of this row in the week: create it.
            if (!row) {
                row = {
                    key: key,
                    project: KimaiApi.projectName(entry),
                    activity: KimaiApi.activityName(entry),
                    days: [0, 0, 0, 0, 0, 0, 0],
                    total: 0,
                    running: false
                }
                byKey[key] = row
                rows.push(row)
            }

            row.days[d] += secs
            row.total += secs
            row.running = row.running || !entry.end
            dayTotals[d] += secs
            total += secs
        }
    }

    rows.sort(function(a, b) { return b.total - a.total })
    return { rows: rows, dayTotals: dayTotals, total: total }
}
