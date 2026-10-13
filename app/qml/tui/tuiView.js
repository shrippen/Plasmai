.pragma library
.import "../../../contents/code/dayModel.js" as DayModel

/**
 * Screens of the terminal client as text: pure functions from a model to
 * lines with ANSI colours. Tui.qml builds the model from the Session and
 * passes translated words in `t`; nothing here knows Qt or the network.
 *
 *   Session ──Tui.qml──▶ model ──main() / day() / week()──▶ text ──▶ Terminal.render
 *
 * Widths are counted on the plain text before colours are added.
 */

const ESC = "\x1b["

/** SGR colours close to Kante's roles on a dark terminal. */
var Style = {
    RESET: ESC + "0m",
    BOLD: ESC + "1m",
    DIM: ESC + "2m",
    PRIMARY: ESC + "33m",
    FOCUS: ESC + "36m",
    DANGER: ESC + "31m",
    OK: ESC + "32m",
    INVERSE: ESC + "7m"
}

const HOURS_SHOWN_MIN = 6
const HOURS_SHOWN_MAX = 22
const QUARTERS = 4
const WEEK_DAYS = 7

function paint(style, text) {
    return style + text + Style.RESET
}

/** `text` cut or padded to exactly `width` characters. */
function fit(text, width) {
    const s = String(text || "")
    if (width <= 0) {
        return ""
    }
    if (s.length > width) {
        return width > 1 ? s.slice(0, width - 1) + "…" : s.slice(0, width)
    }
    return s + " ".repeat(width - s.length)
}

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

/** 5425 → "1:30:25"; seconds always shown, for a running timer. */
function clock(seconds) {
    const s = Math.max(0, Math.floor(seconds))
    return Math.floor(s / 3600) + ":" + pad2(Math.floor(s / 60) % 60) + ":" + pad2(s % 60)
}

/** 5425 → "1:30"; for totals. */
function hm(seconds) {
    const m = Math.round(Math.max(0, seconds) / 60)
    return Math.floor(m / 60) + ":" + pad2(m % 60)
}

/** 13.25 → "13:15". */
function hourLabel(hour) {
    const minutes = Math.round(hour * 60)
    return pad2(Math.floor(minutes / 60)) + ":" + pad2(minutes % 60)
}

function rule(width) {
    return paint(Style.DIM, "─".repeat(Math.max(0, width)))
}

/** Title line and status: "PLASMAI · Demo                online". */
function header(model, width, t) {
    const right = model.statusText || ""
    const left = "PLASMAI · " + (model.profileName || "")
    const gap = Math.max(1, width - left.length - right.length)
    return paint(Style.BOLD + Style.PRIMARY, left) + " ".repeat(gap) + paint(model.statusStyle || Style.DIM, right)
}

function footer(keys, width) {
    return paint(Style.DIM, fit(keys, width))
}

/**
 * Timer, totals and the recent list.
 * model: { profileName, statusText, statusStyle, tracking, activity, project,
 *          elapsed, todaySeconds, weekSeconds, recent: [{ title, sub }], selected, message }
 */
function main(model, size, t) {
    const w = size.columns
    const lines = [header(model, w, t), rule(w)]

    if (model.tracking) {
        lines.push(paint(Style.DANGER, "● ") + paint(Style.BOLD, clock(model.elapsed)) + "  "
                   + fit(model.activity + " · " + model.project, w - 12))
    } else {
        lines.push(paint(Style.DIM, "○ " + t.idle))
    }
    lines.push(paint(Style.DIM, t.today + " " + hm(model.todaySeconds) + " · " + t.week + " " + hm(model.weekSeconds)))
    lines.push("")
    lines.push(paint(Style.BOLD, t.recent))

    // Recent rows with their number key; the selected one inverted.
    const room = Math.max(1, size.rows - lines.length - 3)
    const rows = (model.recent || []).slice(0, room)
    for (let i = 0; i < rows.length; i++) {
        const key = i < 9 ? String(i + 1) : " "
        const plain = fit(key + "  " + rows[i].title + "  " + rows[i].sub, w)
        lines.push(i === model.selected ? paint(Style.INVERSE, plain) : plain)
    }
    if (rows.length === 0) {
        lines.push(paint(Style.DIM, t.noRecent))
    }

    while (lines.length < size.rows - 2) {
        lines.push("")
    }
    lines.push(model.message ? paint(Style.DANGER, fit(model.message, w)) : "")
    lines.push(footer(t.mainKeys, w))
    return lines.join("\n")
}

/**
 * The day as hour rows of four quarters: █ tracked, ░ a gap in the work
 * day, · outside. Then the gaps as a list.
 * model: { title, blocks (DayModel.blocks), workFrom, workTo, untilHour }
 */
function day(model, size, t) {
    const w = size.columns
    const blocks = model.blocks || []
    const lines = [header(model, w, t), rule(w), paint(Style.BOLD, model.title), ""]

    let from = HOURS_SHOWN_MIN
    let to = HOURS_SHOWN_MAX
    for (let i = 0; i < blocks.length; i++) {
        from = Math.min(from, Math.floor(blocks[i].fromHour))
        to = Math.max(to, Math.ceil(blocks[i].toHour))
    }

    const until = Math.min(model.workTo, model.untilHour)
    const gaps = DayModel.gaps(blocks, model.workFrom, until, 15)
    const room = Math.max(1, size.rows - lines.length - 5)
    // Too many hours for the screen: show the latest ones.
    const first = to - from > room ? Math.max(from, to - room) : from

    for (let h = first; h < to && lines.length - 4 < room; h++) {
        let bar = ""
        const labels = []
        for (let q = 0; q < QUARTERS; q++) {
            const mid = h + (q + 0.5) / QUARTERS
            const hit = blocks.filter(function(b) { return b.fromHour <= mid && mid < b.toHour })[0]
            const inGap = gaps.some(function(g) { return g.fromHour <= mid && mid < g.toHour })
            if (hit) {
                bar += paint(hit.running ? Style.DANGER : Style.PRIMARY, "█")
                if (labels.indexOf(hit.label) < 0) {
                    labels.push(hit.label)
                }
            } else {
                bar += inGap ? paint(Style.FOCUS, "░") : paint(Style.DIM, "·")
            }
        }
        lines.push(paint(Style.DIM, pad2(h % 24)) + " " + bar + "  " + fit(labels.join(", "), w - 9))
    }

    lines.push("")
    if (gaps.length === 0) {
        lines.push(paint(Style.OK, t.noGaps))
    } else {
        const parts = gaps.map(function(g) { return hourLabel(g.fromHour) + "–" + hourLabel(g.toHour) + " (" + g.minutes + " min)" })
        lines.push(paint(Style.FOCUS, fit(t.gaps + " " + parts.join(", "), w)))
    }
    while (lines.length < size.rows - 1) {
        lines.push("")
    }
    lines.push(footer(t.subKeys, w))
    return lines.join("\n")
}

/**
 * The week as a table: one row per project and activity, seconds per day.
 * model: { title, grid (DayModel.weekGrid), dayNames [7], todayIndex }
 */
function week(model, size, t) {
    const w = size.columns
    const grid = model.grid || { rows: [], dayTotals: [0, 0, 0, 0, 0, 0, 0], total: 0 }
    const cell = 6
    const label = Math.max(10, w - cell * (WEEK_DAYS + 1) - 1)
    const lines = [header(model, w, t), rule(w), paint(Style.BOLD, model.title), ""]

    let head = fit("", label)
    for (let d = 0; d < WEEK_DAYS; d++) {
        const name = fit(model.dayNames[d], cell - 1) + " "
        head += d === model.todayIndex ? paint(Style.PRIMARY, name) : paint(Style.DIM, name)
    }
    lines.push(head + paint(Style.DIM, "Σ"))

    const room = Math.max(1, size.rows - lines.length - 4)
    const rows = grid.rows.slice(0, room)
    for (let r = 0; r < rows.length; r++) {
        const row = rows[r]
        let line = fit((row.running ? "● " : "") + row.activity + " · " + row.project, label)
        for (let d = 0; d < WEEK_DAYS; d++) {
            const v = row.days[d] > 0 ? hm(row.days[d]) : "·"
            line += fit(v, cell - 1) + " "
        }
        line += hm(row.total)
        lines.push(line)
    }
    if (rows.length === 0) {
        lines.push(paint(Style.DIM, t.noEntries))
    }

    let total = fit(t.total, label)
    for (let d = 0; d < WEEK_DAYS; d++) {
        total += fit(grid.dayTotals[d] > 0 ? hm(grid.dayTotals[d]) : "·", cell - 1) + " "
    }
    lines.push(rule(w))
    lines.push(paint(Style.BOLD, total + hm(grid.total)))
    while (lines.length < size.rows - 1) {
        lines.push("")
    }
    lines.push(footer(t.subKeys, w))
    return lines.join("\n")
}
