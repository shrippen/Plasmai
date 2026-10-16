.pragma library

/**
 * Popup layouts (ROADMAP "Layouts"): which main view the popup and the app
 * show. One shared key, `layout`; the setup wizard asks how someone works
 * and picks the layout from the answer.
 *
 *   wizard answer ──forAnswer()──▶ Layout ──normalize()──▶ view loader
 *
 * Unknown or missing values fall back to CLASSIC, so an older or newer
 * config never leaves the popup empty.
 */

/** Values of the `layout` key. */
var Layout = {
    CLASSIC: "classic",
    TILES: "tiles",
    TIMESHEET: "timesheet",
    DAYBAND: "dayband",
    RING: "ring"
}

/** Wizard answers to "How do you work?". */
var Answer = {
    SWITCH_OFTEN: "switchOften",
    SEE_DAY: "seeDay",
    WEEKLY: "weekly",
    AS_BEFORE: "asBefore"
}

/** Layouts offered in settings only, marked experimental. */
var EXPERIMENTAL = [Layout.RING]

const ANSWER_LAYOUT = {
    switchOften: Layout.TILES,
    seeDay: Layout.DAYBAND,
    weekly: Layout.TIMESHEET,
    asBefore: Layout.CLASSIC
}

/** The stored value if known, else CLASSIC. */
function normalize(value) {
    const v = String(value || "")
    const known = Object.keys(Layout).some(function(k) { return Layout[k] === v })
    return known ? v : Layout.CLASSIC
}

/** Layout for a wizard answer; CLASSIC for an unknown answer. */
function forAnswer(answer) {
    return ANSWER_LAYOUT[answer] || Layout.CLASSIC
}

/** Wizard answers in display order; the last keeps today's popup. */
function answers() {
    return [Answer.SWITCH_OFTEN, Answer.SEE_DAY, Answer.WEEKLY, Answer.AS_BEFORE]
}

function isExperimental(layout) {
    return EXPERIMENTAL.indexOf(normalize(layout)) >= 0
}
