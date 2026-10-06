.pragma library

/**
 * First-start wizard (SetupWizard.qml): which steps a platform needs, what the
 * system check means, and what the wizard writes. Pure functions, no I/O, so
 * the Plasmoid and the app (Linux, Plasma Mobile, Android, Windows) share them.
 *
 *   Platform.checkSystem() ──▶ assess() ──▶ steps()
 *
 *   [System] ──▶ Look ──▶ Service ──▶ Access ──▶ Day
 *       │            │                      │          │
 *   only when the  visualStyle,          test, then  work hours, place,
 *   token cannot   applied at once       store token reminder (all optional)
 *   be stored
 *
 * The System step exists only where something blocks storing the token: the
 * Plasmoid needs secret-tool and a Secret Service (KWallet). The app stores
 * through QtKeychain and has nothing to install, so it starts at Look.
 */

var Step = {
    SYSTEM: "system",
    LOOK: "look",
    SERVICE: "service",
    ACCESS: "access",
    DAY: "day"
}

/** Findings of the system check (assess()). */
var Issue = {
    SECRET_TOOL: "secretTool",
    SECRET_SERVICE: "secretService",
    NOTIFY_SEND: "notifySend"
}

var Severity = {
    BLOCKING: "blocking",
    OPTIONAL: "optional"
}

/** Keep the System step once shown, so fixing it does not shift the steps. */
var SystemStep = {
    AUTO: "auto",
    KEEP: "keep"
}

/** Values of the system check's "secretService" key. */
var Availability = {
    YES: "yes",
    NO: "no",
    UNKNOWN: "unknown"
}

var Tool = {
    SECRET_TOOL: "secret-tool",
    NOTIFY_SEND: "notify-send"
}

/** Values of visualStyle (KanteStyle.Kind): the platform theme, Kante, Kante Light. */
var Look = {
    SYSTEM: 0,
    KANTE: 1,
    KANTE_LIGHT: 2
}

var UrlProblem = {
    NONE: "",
    MISSING: "missing",
    INVALID: "invalid"
}

var UrlNote = {
    INSECURE: "insecure",
    TRIMMED: "trimmed",
    SCHEME_ADDED: "schemeAdded"
}

/** Name of the untouched first profile (profiles.js defaultProfiles()). */
var DEFAULT_PROFILE_NAME = "Default"
var DEFAULT_PROFILE_ID = "default"

var HTTP = "http://"
var HTTPS = "https://"

/** Hosts where plain http does not leave the machine. */
var LOCAL_HOSTS = ["localhost", "127.0.0.1", "[::1]"]

/** Install commands per package manager; the package that brings each tool. */
var PACKAGES = {
    apt: { command: "sudo apt install ", "secret-tool": "libsecret-tools", "notify-send": "libnotify-bin" },
    pacman: { command: "sudo pacman -S ", "secret-tool": "libsecret", "notify-send": "libnotify" },
    dnf: { command: "sudo dnf install ", "secret-tool": "libsecret", "notify-send": "libnotify" },
    zypper: { command: "sudo zypper install ", "secret-tool": "secret-tool", "notify-send": "libnotify-tools" }
}

/** os-release ID / ID_LIKE words per package manager (ID_LIKE covers neon, Manjaro, Nobara, …). */
var FAMILIES = [
    { manager: "apt", ids: ["debian", "ubuntu"] },
    { manager: "pacman", ids: ["arch"] },
    { manager: "dnf", ids: ["fedora", "rhel"] },
    { manager: "zypper", ids: ["suse", "opensuse"] }
]

/** "08:00" → minutes since midnight, -1 when it is no clock time. */
function clockMinutes(text) {
    var m = /^(\d{1,2}):(\d{2})$/.exec(String(text || "").trim())
    if (!m) {
        return -1
    }

    var h = Number(m[1])
    var min = Number(m[2])
    if (h > 23 || min > 59) {
        return -1
    }
    return h * 60 + min
}

/** Package manager of an os-release ID / ID_LIKE pair, "" when unknown. */
function packageManager(osId, osLike) {
    var words = (String(osId || "") + " " + String(osLike || "")).toLowerCase().split(/\s+/)

    for (var f = 0; f < FAMILIES.length; f++) {
        for (var w = 0; w < words.length; w++) {
            // "opensuse-tumbleweed", "opensuse-leap": the family name is a prefix.
            var word = words[w].split("-")[0]
            if (FAMILIES[f].ids.indexOf(word) >= 0) {
                return FAMILIES[f].manager
            }
        }
    }
    return ""
}

/** Shell command that installs a Tool on this distribution, "" when unknown. */
function installCommand(tool, osId, osLike) {
    var manager = packageManager(osId, osLike)
    if (!manager) {
        return ""
    }
    return PACKAGES[manager].command + PACKAGES[manager][tool]
}

/**
 * Findings of a system check, blocking first.
 * check: { secretTool, secretService, notifySend, osId, osLike }; a missing key
 * means "not checked on this platform" (the app reports none).
 * Returns [{ id: Issue, severity: Severity, command }].
 */
function assess(check) {
    var c = check || {}
    var issues = []

    // Without secret-tool the Secret Service cannot be asked: one finding, not two.
    if (c.secretTool === false) {
        issues.push({ id: Issue.SECRET_TOOL, severity: Severity.BLOCKING,
                      command: installCommand(Tool.SECRET_TOOL, c.osId, c.osLike) })
    } else if (c.secretService === Availability.NO) {
        issues.push({ id: Issue.SECRET_SERVICE, severity: Severity.BLOCKING, command: "" })
    }

    if (c.notifySend === false) {
        issues.push({ id: Issue.NOTIFY_SEND, severity: Severity.OPTIONAL,
                      command: installCommand(Tool.NOTIFY_SEND, c.osId, c.osLike) })
    }
    return issues
}

function hasBlocking(issues) {
    return findIssue(issues, Severity.BLOCKING) !== null
}

/** First issue with this severity, or null. */
function findIssue(issues, severity) {
    var list = issues || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].severity === severity) {
            return list[i]
        }
    }
    return null
}

/** The issue with this id, or null. */
function issueById(issues, id) {
    var list = issues || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id) {
            return list[i]
        }
    }
    return null
}

/** Steps for these findings; SystemStep.KEEP keeps System after it was fixed. */
function steps(issues, systemStep) {
    var list = [Step.LOOK, Step.SERVICE, Step.ACCESS, Step.DAY]
    if (systemStep === SystemStep.KEEP || hasBlocking(issues)) {
        list.unshift(Step.SYSTEM)
    }
    return list
}

/** shared.json keys of the Look step: the chosen visualStyle, or {} when it is no Look. */
function lookPatch(style) {
    var v = Number(style)
    if (v !== Look.SYSTEM && v !== Look.KANTE && v !== Look.KANTE_LIGHT) {
        return {}
    }
    return { visualStyle: v }
}

/**
 * A pasted token without what copying adds: spaces, line breaks and a
 * "Bearer " prefix copied from an API example. Tokens never contain blanks.
 */
function cleanToken(text) {
    var s = String(text || "").trim().replace(/^bearer\s+/i, "")
    return s.replace(/\s+/g, "")
}

function isLocalHost(host) {
    var h = String(host || "").toLowerCase()
    return LOCAL_HOSTS.indexOf(h) >= 0 || /\.local$/.test(h)
}

/**
 * The server address as the provider needs it.
 *   "kimai.example.com"                    → https://kimai.example.com (schemeAdded)
 *   "https://kimai.example.com/de/timesheet/" → https://kimai.example.com (trimmed)
 *   "https://kimai.example.com/api/doc"    → https://kimai.example.com (trimmed)
 *   "http://kimai.example.com"             → kept, note insecure
 * Kimai only: a Kimai page or API address is cut back to the instance; the
 * other services' default URLs carry paths of their own and stay as entered.
 * Returns { url, problem: UrlProblem, notes: [UrlNote] }.
 */
function checkUrl(providerId, text) {
    var notes = []
    var s = String(text || "").trim()
    if (!s) {
        return { url: "", problem: UrlProblem.MISSING, notes: notes }
    }

    // Block: scheme. A bare host gets https.
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(s)) {
        s = HTTPS + s
        notes.push(UrlNote.SCHEME_ADDED)
    }
    s = s.replace(/^(https?)(:\/\/)/i, function(m, scheme, sep) { return scheme.toLowerCase() + sep })
    var m = /^(https?):\/\/([^\/?#\s]+)([^?#\s]*)/.exec(s)
    if (!m) {
        return { url: "", problem: UrlProblem.INVALID, notes: notes }
    }

    // Block: path. Kimai pages are /<locale>/<page>, the API is /api/….
    var path = m[3].replace(/\/+$/, "")
    if (providerId === "kimai") {
        var cut = path.replace(/\/api(\/.*)?$/, "").replace(/\/[a-z]{2}(_[a-z]{2})?\/[^\/].*$/i, "")
        if (cut !== path) {
            notes.push(UrlNote.TRIMMED)
            path = cut
        }
    }

    var host = m[2].replace(/:\d+$/, "")
    if (m[1] === "http" && !isLocalHost(host)) {
        notes.push(UrlNote.INSECURE)
    }
    return { url: m[1] + "://" + m[2] + path, problem: UrlProblem.NONE, notes: notes }
}

function hasNote(result, note) {
    return !!result && (result.notes || []).indexOf(note) >= 0
}

/**
 * Profiles after the wizard: the active profile (or the first) gets the chosen
 * service and address; others stay. An untouched "Default" is renamed to the
 * service. Returns { profiles, profileId }.
 */
function applyService(profiles, activeId, providerId, providerName, url) {
    var list = (profiles || []).slice()
    var index = 0
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === activeId) {
            index = i
            break
        }
    }

    var base = list.length > 0 ? list[index] : { id: DEFAULT_PROFILE_ID, name: DEFAULT_PROFILE_NAME }
    var p = {}
    for (var k in base) {
        p[k] = base[k]
    }
    p.provider = providerId
    p.url = url
    if (!p.name || p.name === DEFAULT_PROFILE_NAME) {
        p.name = providerName
    }

    if (list.length === 0) {
        list.push(p)
    } else {
        list[index] = p
    }
    return { profiles: list, profileId: p.id }
}

/** Account ids a connection test returns (Clockify, Toggl, SolidTime need them later). */
function withConnectionMeta(profile, data) {
    var p = {}
    for (var k in profile) {
        p[k] = profile[k]
    }
    if (!data) {
        return p
    }

    var keys = ["workspaceId", "userId", "organizationId", "memberId"]
    for (var i = 0; i < keys.length; i++) {
        if (data[keys[i]]) {
            p[keys[i]] = data[keys[i]]
        }
    }
    return p
}

/** Name to greet: Kimai alias, else name, username or e-mail ("" when none). */
function userLabel(user) {
    if (!user) {
        return ""
    }
    return String(user.alias || user.name || user.username || user.email || "")
}

/**
 * shared.json keys of the Day step. Only what was set: an empty place keeps
 * the current one, invalid hours keep the current hours.
 * day: { begin, end, place: { displayName, latitude, longitude } | null, remind }
 */
function dayPatch(day) {
    var d = day || {}
    var patch = {}

    var begin = clockMinutes(d.begin)
    var end = clockMinutes(d.end)
    if (begin >= 0 && end > begin) {
        patch.workDayBegin = String(d.begin).trim()
        patch.workDayEnd = String(d.end).trim()
    }

    var place = d.place
    if (place && isFinite(place.latitude) && isFinite(place.longitude)) {
        patch.latitude = Number(place.latitude)
        patch.longitude = Number(place.longitude)
        patch.locationName = String(place.displayName || "")
    }

    if (typeof d.remind === "boolean") {
        patch.notifyForgotToStart = d.remind
    }
    return patch
}

/** Begin before end, both clock times. */
function validHours(begin, end) {
    var b = clockMinutes(begin)
    return b >= 0 && clockMinutes(end) > b
}

/** First part of a Nominatim name: "Hamburg, Deutschland" → "Hamburg". */
function shortPlace(displayName) {
    return String(displayName || "").split(",")[0].trim()
}
