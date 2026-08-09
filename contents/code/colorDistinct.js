.pragma library

/**
 * Within-category color distinction.
 * Same / similar Kimai colors are shifted (hue) so items in one category
 * stay visually distinct. The same color may still appear across categories.
 */

var DEFAULT_COLOR = "#d2d6de"
var GOLDEN_ANGLE = 137.508
/** Floor when auto-lowering threshold — keep high enough that pastels stay distinct. */
var MIN_SIMILARITY = 12
/** Bump when distinction algorithm changes so cached maps are invalidated. */
var CACHE_VERSION = 3
/** How many vivid palette slots to try (golden-angle spread). */
var PALETTE_SIZE = 72
/** Soft minimum hue gap; scaled down when many colors are already assigned. */
var MIN_HUE_SEP = 15 / 360

var _enabled = true
/** 0–100: colors closer than this % are "similar" (perceptual + RGB). */
var _similarityPercent = 22
/** Effective threshold actually used per category after auto-lowering. */
var _effectiveSimilarity = {
    customer: 22,
    project: 22,
    activity: 22
}
/** Fingerprint of last successful rebuild inputs; skip recompute when unchanged. */
var _cacheKey = ""
var _maps = {
    customer: {},
    project: {},
    activity: {}
}
var _originals = {
    customer: {},
    project: {},
    activity: {}
}

function clamp01(n) {
    return Math.max(0, Math.min(1, n))
}

function configure(enabled, similarityPercent) {
    var nextEnabled = !!enabled
    var p = Number(similarityPercent)
    if (isNaN(p)) {
        p = 22
    }
    var nextPercent = Math.max(MIN_SIMILARITY, Math.min(80, Math.round(p)))
    if (nextEnabled !== _enabled || nextPercent !== _similarityPercent) {
        _cacheKey = ""
    }
    _enabled = nextEnabled
    _similarityPercent = nextPercent
}

function invalidateCache() {
    _cacheKey = ""
}

function isEnabled() {
    return _enabled
}

function similarityPercent() {
    return _similarityPercent
}

/** Threshold used for the last rebuild of a category (may be below configured). */
function effectiveSimilarityPercent(category) {
    if (category && _effectiveSimilarity[category] !== undefined) {
        return _effectiveSimilarity[category]
    }
    return Math.min(
        _effectiveSimilarity.customer,
        _effectiveSimilarity.project,
        _effectiveSimilarity.activity
    )
}

function normalizeHex(color) {
    var c = String(color || "").trim()
    if (!c) {
        return DEFAULT_COLOR
    }
    if (c.charAt(0) !== "#") {
        c = "#" + c
    }
    // Expand #RGB
    if (c.length === 4) {
        c = "#" + c.charAt(1) + c.charAt(1) + c.charAt(2) + c.charAt(2) + c.charAt(3) + c.charAt(3)
    }
    if (c.length >= 7) {
        return c.slice(0, 7).toLowerCase()
    }
    return DEFAULT_COLOR
}

function hexToRgb(hex) {
    var h = normalizeHex(hex).slice(1)
    return {
        r: parseInt(h.slice(0, 2), 16) || 0,
        g: parseInt(h.slice(2, 4), 16) || 0,
        b: parseInt(h.slice(4, 6), 16) || 0
    }
}

function rgbToHex(r, g, b) {
    function byte(n) {
        var v = Math.max(0, Math.min(255, Math.round(n)))
        var s = v.toString(16)
        return s.length === 1 ? "0" + s : s
    }
    return "#" + byte(r) + byte(g) + byte(b)
}

function rgbToHsl(r, g, b) {
    r /= 255
    g /= 255
    b /= 255
    var max = Math.max(r, g, b)
    var min = Math.min(r, g, b)
    var h = 0
    var s = 0
    var l = (max + min) / 2
    if (max !== min) {
        var d = max - min
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
        if (max === r) {
            h = ((g - b) / d + (g < b ? 6 : 0)) / 6
        } else if (max === g) {
            h = ((b - r) / d + 2) / 6
        } else {
            h = ((r - g) / d + 4) / 6
        }
    }
    return { h: h, s: s, l: l }
}

function hue2rgb(p, q, t) {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
}

function hslToRgb(h, s, l) {
    var r
    var g
    var b
    if (s === 0) {
        r = g = b = l
    } else {
        var q = l < 0.5 ? l * (1 + s) : l + s - l * s
        var p = 2 * l - q
        r = hue2rgb(p, q, h + 1 / 3)
        g = hue2rgb(p, q, h)
        b = hue2rgb(p, q, h - 1 / 3)
    }
    return { r: r * 255, g: g * 255, b: b * 255 }
}

function hueDistance(h1, h2) {
    var d = Math.abs(h1 - h2)
    return Math.min(d, 1 - d)
}

function adaptiveHueSep(assignedCount) {
    if (assignedCount <= 1) {
        return MIN_HUE_SEP
    }
    return Math.min(MIN_HUE_SEP, 0.42 / assignedCount)
}

/**
 * Distance 0–100 combining RGB with HSL so washed pastels near each other
 * still count as similar (RGB alone under-separates them).
 */
function colorDistancePercent(hexA, hexB) {
    var a = hexToRgb(hexA)
    var b = hexToRgb(hexB)
    var dr = a.r - b.r
    var dg = a.g - b.g
    var db = a.b - b.b
    var rgbDist = (Math.sqrt(dr * dr + dg * dg + db * db) / Math.sqrt(3 * 255 * 255)) * 100

    var ha = rgbToHsl(a.r, a.g, a.b)
    var hb = rgbToHsl(b.r, b.g, b.b)
    var meanS = (ha.s + hb.s) / 2
    var dh = hueDistance(ha.h, hb.h) * 2
    var hueScore = dh * 100 * (0.2 + 0.8 * meanS)
    var satScore = Math.abs(ha.s - hb.s) * 40
    var litScore = Math.abs(ha.l - hb.l) * 50
    if (ha.l > 0.55 && hb.l > 0.55 && meanS > 0.12 && meanS < 0.55) {
        hueScore *= 1.5
    }
    var perceptual = Math.min(100, hueScore + satScore + litScore)
    return Math.max(rgbDist, perceptual)
}

function areSimilar(hexA, hexB, thresholdPercent, assignedCount) {
    var thr = (typeof thresholdPercent === "number") ? thresholdPercent : _similarityPercent
    if (colorDistancePercent(hexA, hexB) < thr) {
        return true
    }
    var a = hexToRgb(hexA)
    var b = hexToRgb(hexB)
    var ha = rgbToHsl(a.r, a.g, a.b)
    var hb = rgbToHsl(b.r, b.g, b.b)
    if (ha.s >= 0.25 && hb.s >= 0.25) {
        var sep = adaptiveHueSep(typeof assignedCount === "number" ? assignedCount : 8)
        if (hueDistance(ha.h, hb.h) < sep) {
            return true
        }
    }
    return false
}

/**
 * High-chroma palette slot — used when the Kimai color must be replaced.
 * Spreads by golden angle with rotating lightness so N greys become N distinct hues.
 */
function paletteColor(index) {
    var i = Math.max(0, Math.floor(index))
    var h = ((GOLDEN_ANGLE * i) % 360) / 360
    if (h < 0) {
        h += 1
    }
    var tier = i % 5
    var s = [0.78, 0.70, 0.82, 0.66, 0.74][tier]
    var l = [0.42, 0.55, 0.48, 0.62, 0.38][tier]
    var out = hslToRgb(h, s, l)
    return rgbToHex(out.r, out.g, out.b)
}

function shiftHue(hex, degrees) {
    var rgb = hexToRgb(hex)
    var hsl = rgbToHsl(rgb.r, rgb.g, rgb.b)
    if (hsl.s < 0.22) {
        hsl.s = 0.72
        if (hsl.l < 0.3) {
            hsl.l = 0.45
        } else if (hsl.l > 0.75) {
            hsl.l = 0.52
        }
    }
    hsl.h = (hsl.h + (degrees / 360)) % 1
    if (hsl.h < 0) {
        hsl.h += 1
    }
    var out = hslToRgb(hsl.h, hsl.s, hsl.l)
    return rgbToHex(out.r, out.g, out.b)
}

function shiftLightness(hex, delta) {
    var rgb = hexToRgb(hex)
    var hsl = rgbToHsl(rgb.r, rgb.g, rgb.b)
    hsl.l = clamp01(hsl.l + delta)
    if (hsl.s < 0.22) {
        hsl.s = 0.7
    }
    var out = hslToRgb(hsl.h, hsl.s, hsl.l)
    return rgbToHex(out.r, out.g, out.b)
}

/**
 * Candidate 0 = keep original. Later candidates prefer the vivid palette
 * (not washed hue-shifts of the same grey, which all looked like pale cyan).
 */
function colorCandidate(original, attempt) {
    if (attempt <= 0) {
        return normalizeHex(original)
    }
    if (attempt <= PALETTE_SIZE) {
        return paletteColor(attempt - 1)
    }
    var extra = attempt - PALETTE_SIZE
    return shiftHue(original, GOLDEN_ANGLE * extra)
}

function clashesAny(color, assigned, thr) {
    for (var j = 0; j < assigned.length; j++) {
        if (areSimilar(color, assigned[j], thr, assigned.length)) {
            return true
        }
    }
    return false
}

/** True if every pair in assigned is far enough apart. */
function allDistinct(assigned, thr) {
    for (var i = 0; i < assigned.length; i++) {
        for (var j = i + 1; j < assigned.length; j++) {
            if (areSimilar(assigned[i], assigned[j], thr, assigned.length)) {
                return false
            }
        }
    }
    return true
}

function minDistanceToAssigned(color, assigned) {
    if (!assigned.length) {
        return 100
    }
    var best = 100
    for (var j = 0; j < assigned.length; j++) {
        var d = colorDistancePercent(color, assigned[j])
        if (d < best) {
            best = d
        }
    }
    return best
}

var MAX_COLOR_ATTEMPTS = PALETTE_SIZE + 48

/**
 * Pick a color that does not clash with any already-assigned (including prior shifts).
 * Returns null if no candidate works at this threshold.
 */
function pickDistinctColor(original, assigned, thr) {
    for (var attempt = 0; attempt < MAX_COLOR_ATTEMPTS; attempt++) {
        var color = colorCandidate(original, attempt)
        if (!clashesAny(color, assigned, thr)) {
            return color
        }
    }
    return null
}

/**
 * Assign colors for one threshold. Every new color (shifted or not) is checked
 * against all previously assigned colors. Final pair-wise verify.
 * Returns map or null if impossible at this threshold.
 */
function tryDistinguishAtThreshold(list, thr) {
    var assigned = []
    var map = {}
    for (var i = 0; i < list.length; i++) {
        var ent = list[i]
        if (!ent || ent.id === null || ent.id === undefined) {
            continue
        }
        var id = String(ent.id)
        var original = normalizeHex(ent.color)
        var color = pickDistinctColor(original, assigned, thr)
        if (!color) {
            return null
        }
        assigned.push(color)
        map[id] = color
    }
    if (!allDistinct(assigned, thr)) {
        return null
    }
    return map
}

/**
 * Last resort at MIN_SIMILARITY: always assign, maximizing separation.
 */
function distinguishBestEffort(list, thr) {
    var assigned = []
    var map = {}
    for (var i = 0; i < list.length; i++) {
        var ent = list[i]
        if (!ent || ent.id === null || ent.id === undefined) {
            continue
        }
        var id = String(ent.id)
        var original = normalizeHex(ent.color)
        var color = pickDistinctColor(original, assigned, thr)
        if (!color) {
            var best = original
            var bestDist = -1
            for (var attempt = 0; attempt < MAX_COLOR_ATTEMPTS; attempt++) {
                var cand = colorCandidate(original, attempt)
                var d = minDistanceToAssigned(cand, assigned)
                if (d > bestDist) {
                    bestDist = d
                    best = cand
                }
            }
            color = best
        }
        assigned.push(color)
        map[id] = color
    }
    return map
}

/**
 * entities: [{ id, name?, color }]
 * Returns { map, threshold }
 */
function distinguishCategory(entities, thresholdPercent) {
    var startThr = (typeof thresholdPercent === "number") ? thresholdPercent : _similarityPercent
    startThr = Math.max(MIN_SIMILARITY, Math.min(80, Math.round(startThr)))
    var list = (entities || []).slice()
    list.sort(function(a, b) {
        return String(a.id).localeCompare(String(b.id), undefined, { numeric: true })
    })

    var thr = startThr
    while (thr >= MIN_SIMILARITY) {
        var map = tryDistinguishAtThreshold(list, thr)
        if (map) {
            return { map: map, threshold: thr }
        }
        thr -= 1
    }
    return {
        map: distinguishBestEffort(list, MIN_SIMILARITY),
        threshold: MIN_SIMILARITY
    }
}

function rebuild(customers, projects, activities, force) {
    function pack(list) {
        var out = []
        for (var i = 0; i < (list || []).length; i++) {
            var item = list[i]
            if (!item || item.id === null || item.id === undefined) {
                continue
            }
            out.push({
                id: item.id,
                name: item.name || item.title || ("#" + item.id),
                color: item.color || DEFAULT_COLOR
            })
        }
        return out
    }

    function fingerprint(list) {
        var parts = []
        for (var i = 0; i < list.length; i++) {
            parts.push(String(list[i].id) + "=" + normalizeHex(list[i].color))
        }
        parts.sort()
        return parts.join(";")
    }

    var custList = pack(customers)
    var projList = pack(projects)
    var actList = pack(activities)
    var key = "v" + CACHE_VERSION
        + "|" + (_enabled ? "1" : "0")
        + "|" + _similarityPercent
        + "|c:" + fingerprint(custList)
        + "|p:" + fingerprint(projList)
        + "|a:" + fingerprint(actList)

    if (!force && key === _cacheKey) {
        return false
    }

    var origC = {}
    var origP = {}
    var origA = {}
    var i
    for (i = 0; i < custList.length; i++) {
        origC[String(custList[i].id)] = normalizeHex(custList[i].color)
    }
    for (i = 0; i < projList.length; i++) {
        origP[String(projList[i].id)] = normalizeHex(projList[i].color)
    }
    for (i = 0; i < actList.length; i++) {
        origA[String(actList[i].id)] = normalizeHex(actList[i].color)
    }
    _originals = { customer: origC, project: origP, activity: origA }

    if (!_enabled) {
        _maps = { customer: origC, project: origP, activity: origA }
        _effectiveSimilarity = {
            customer: _similarityPercent,
            project: _similarityPercent,
            activity: _similarityPercent
        }
        _cacheKey = key
        return true
    }
    var cust = distinguishCategory(custList, _similarityPercent)
    var proj = distinguishCategory(projList, _similarityPercent)
    var act = distinguishCategory(actList, _similarityPercent)
    _maps = {
        customer: cust.map,
        project: proj.map,
        activity: act.map
    }
    _effectiveSimilarity = {
        customer: cust.threshold,
        project: proj.threshold,
        activity: act.threshold
    }
    _cacheKey = key
    return true
}

function adjust(category, id, hex) {
    var c = normalizeHex(hex)
    if (!_enabled || id === null || id === undefined || id === "") {
        return c
    }
    var map = _maps[category]
    if (map && map[String(id)]) {
        return map[String(id)]
    }
    return c
}

function originalOf(category, id) {
    var map = _originals[category]
    if (map && map[String(id)]) {
        return map[String(id)]
    }
    return DEFAULT_COLOR
}

function mapFor(category) {
    return _maps[category] || {}
}

function originalsFor(category) {
    return _originals[category] || {}
}

/**
 * Maintenance view: only groups where originals clash / were shifted.
 * Each group lists the unshifted keeper first, then shifted siblings.
 * Unique-enough colors (no clash) are omitted.
 *
 * Returns [{
 *   originalColor,  // keeper's Kimai color
 *   entries: [{ id, name, original, display, shifted, keeper }]
 * }]
 */
function maintenanceGroups(category, entities) {
    var thr = _similarityPercent
    var rows = []
    var i
    for (i = 0; i < (entities || []).length; i++) {
        var e = entities[i]
        if (!e || e.id === null || e.id === undefined) {
            continue
        }
        var id = String(e.id)
        var original = normalizeHex(e.color || DEFAULT_COLOR)
        var display = adjust(category, id, original)
        rows.push({
            id: e.id,
            name: e.name || e.title || ("#" + e.id),
            original: original,
            display: display,
            shifted: display.toLowerCase() !== original.toLowerCase()
        })
    }

    if (!_enabled) {
        return []
    }

    var keepers = []
    var shifted = []
    for (i = 0; i < rows.length; i++) {
        if (rows[i].shifted) {
            shifted.push(rows[i])
        } else {
            keepers.push(rows[i])
        }
    }

    // No shifts → nothing to show
    if (shifted.length === 0) {
        return []
    }

    var usedShifted = {}
    var groups = []

    function attachSimilarShifted(keeper) {
        var members = [{
            id: keeper.id,
            name: keeper.name,
            original: keeper.original,
            display: keeper.display,
            shifted: false,
            keeper: true
        }]
        for (var s = 0; s < shifted.length; s++) {
            var row = shifted[s]
            var sid = String(row.id)
            if (usedShifted[sid]) {
                continue
            }
            // Same / similar Kimai color as the keeper
            if (areSimilar(row.original, keeper.original, thr)) {
                usedShifted[sid] = true
                members.push({
                    id: row.id,
                    name: row.name,
                    original: row.original,
                    display: row.display,
                    shifted: true,
                    keeper: false
                })
            }
        }
        return members
    }

    // Prefer keepers that actually “own” a clash (have similar shifted siblings)
    for (i = 0; i < keepers.length; i++) {
        var members = attachSimilarShifted(keepers[i])
        if (members.length > 1) {
            groups.push({
                originalColor: keepers[i].original,
                entries: members
            })
        }
    }

    // Remaining shifted rows with no keeper (e.g. all in a set were shifted vs each other)
    var orphans = []
    for (i = 0; i < shifted.length; i++) {
        if (!usedShifted[String(shifted[i].id)]) {
            orphans.push(shifted[i])
        }
    }
    while (orphans.length > 0) {
        var seed = orphans[0]
        var cluster = [{
            id: seed.id,
            name: seed.name,
            original: seed.original,
            display: seed.display,
            shifted: true,
            keeper: false
        }]
        orphans = orphans.slice(1)
        var rest = []
        for (i = 0; i < orphans.length; i++) {
            if (areSimilar(orphans[i].original, seed.original, thr)) {
                cluster.push({
                    id: orphans[i].id,
                    name: orphans[i].name,
                    original: orphans[i].original,
                    display: orphans[i].display,
                    shifted: true,
                    keeper: false
                })
            } else {
                rest.push(orphans[i])
            }
        }
        orphans = rest
        // First in cluster acts as visual head even if shifted
        cluster[0].keeper = true
        groups.push({
            originalColor: seed.original,
            entries: cluster
        })
    }

    // Sort groups by original color (hue then lightness) for a coherent list
    groups.sort(function(a, b) {
        var ha = rgbToHsl(hexToRgb(a.originalColor).r, hexToRgb(a.originalColor).g, hexToRgb(a.originalColor).b)
        var hb = rgbToHsl(hexToRgb(b.originalColor).r, hexToRgb(b.originalColor).g, hexToRgb(b.originalColor).b)
        if (ha.h !== hb.h) {
            return ha.h - hb.h
        }
        return ha.l - hb.l
    })

    return groups
}

/** Flat rows for counting; prefers grouped maintenance view. */
function maintenanceRows(category, entities) {
    var groups = maintenanceGroups(category, entities)
    var flat = []
    for (var g = 0; g < groups.length; g++) {
        var entries = groups[g].entries || []
        for (var i = 0; i < entries.length; i++) {
            flat.push(entries[i])
        }
    }
    return flat
}

function flattenActivitiesByProject(activitiesByProject, extraList) {
    var map = {}
    var list = extraList || []
    var i
    for (i = 0; i < list.length; i++) {
        if (list[i] && list[i].id !== null && list[i].id !== undefined) {
            map[String(list[i].id)] = list[i]
        }
    }
    var byProject = activitiesByProject || {}
    for (var key in byProject) {
        if (!byProject.hasOwnProperty(key)) {
            continue
        }
        var acts = byProject[key] || []
        for (i = 0; i < acts.length; i++) {
            if (acts[i] && acts[i].id !== null && acts[i].id !== undefined) {
                map[String(acts[i].id)] = acts[i]
            }
        }
    }
    var out = []
    for (var id in map) {
        if (map.hasOwnProperty(id)) {
            out.push(map[id])
        }
    }
    return out
}
