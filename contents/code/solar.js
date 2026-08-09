.pragma library

/**
 * Approximate local-time sunrise/sunset and moonrise/moonset as fractions of a
 * 24h civil day [0, 1]. Sun uses NOAA zenith 90.833°. Moon uses a compact
 * ecliptic approximation sampled for horizon crossings (good enough for UI).
 */

function daySolarFractions(date, latitude, longitude) {
    var lat = Number(latitude)
    var lon = Number(longitude)
    if (isNaN(lat) || isNaN(lon)) {
        return { sunrise: 6 / 24, sunset: 18 / 24, valid: false }
    }
    lat = Math.max(-89.9, Math.min(89.9, lat))
    lon = Math.max(-180, Math.min(180, lon))

    var day = date || new Date()
    var year = day.getFullYear()
    var month = day.getMonth() + 1
    var dayOfMonth = day.getDate()

    var n1 = Math.floor(275 * month / 9)
    var n2 = Math.floor((month + 9) / 12)
    var n3 = (1 + Math.floor((year - 4 * Math.floor(year / 4) + 2) / 3))
    var n = n1 - (n2 * n3) + dayOfMonth - 30

    var lngHour = lon / 15

    function eventHours(isSunrise) {
        var t = isSunrise ? (n + ((6 - lngHour) / 24)) : (n + ((18 - lngHour) / 24))
        var m = (0.9856 * t) - 3.289
        var l = m + (1.916 * Math.sin(rad(m))) + (0.020 * Math.sin(rad(2 * m))) + 282.634
        l = norm360(l)
        var ra = deg(Math.atan(0.91764 * Math.tan(rad(l))))
        ra = norm360(ra)
        var lQuad = Math.floor(l / 90) * 90
        var raQuad = Math.floor(ra / 90) * 90
        ra = ra + (lQuad - raQuad)
        ra = ra / 15

        var sinDec = 0.39782 * Math.sin(rad(l))
        var cosDec = Math.cos(Math.asin(sinDec))
        var cosH = (Math.cos(rad(90.833)) - (sinDec * Math.sin(rad(lat))))
                   / (cosDec * Math.cos(rad(lat)))

        if (cosH > 1) {
            return isSunrise ? null : 24
        }
        if (cosH < -1) {
            return isSunrise ? 0 : null
        }

        var h = isSunrise
            ? 360 - deg(Math.acos(cosH))
            : deg(Math.acos(cosH))
        h = h / 15
        var localT = h + ra - (0.06571 * t) - 6.622
        var ut = localT - lngHour
        ut = ((ut % 24) + 24) % 24

        var offsetHours = -day.getTimezoneOffset() / 60
        var local = ut + offsetHours
        local = ((local % 24) + 24) % 24
        return local
    }

    var rise = eventHours(true)
    var set = eventHours(false)

    if (rise === null && set === 24) {
        return { sunrise: 0, sunset: 0, valid: true, polarNight: true, up: false }
    }
    if (rise === 0 && set === null) {
        return { sunrise: 0, sunset: 1, valid: true, polarDay: true, up: true }
    }

    var sunrise = (typeof rise === "number") ? rise / 24 : 6 / 24
    var sunset = (typeof set === "number") ? set / 24 : 18 / 24
    if (sunset <= sunrise) {
        sunset = Math.min(1, sunrise + 1 / 24)
    }
    var nowFrac = fractionOfLocalDay(day)
    return {
        sunrise: sunrise,
        sunset: sunset,
        valid: true,
        up: isUpInSpan(sunrise, sunset, nowFrac, false)
    }
}

/**
 * Moonrise / moonset as day fractions. May wrap midnight (moonrise > moonset).
 */
function dayLunarFractions(date, latitude, longitude) {
    var lat = Number(latitude)
    var lon = Number(longitude)
    if (isNaN(lat) || isNaN(lon)) {
        return { moonrise: 0.7, moonset: 0.3, valid: false, wraps: true, up: false }
    }
    lat = Math.max(-89.9, Math.min(89.9, lat))
    lon = Math.max(-180, Math.min(180, lon))

    var day = date || new Date()
    var dayStart = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 0, 0, 0, 0)
    var samples = []
    var stepMs = 10 * 60 * 1000
    var i
    for (i = 0; i <= 24 * 6; i++) {
        var t = new Date(dayStart.getTime() + i * stepMs)
        samples.push({
            frac: i / (24 * 6),
            alt: moonAltitudeDeg(t, lat, lon)
        })
    }

    var rises = []
    var sets = []
    for (i = 1; i < samples.length; i++) {
        var a0 = samples[i - 1].alt
        var a1 = samples[i].alt
        if (a0 < 0 && a1 >= 0) {
            rises.push(lerpCrossing(samples[i - 1].frac, a0, samples[i].frac, a1))
        } else if (a0 >= 0 && a1 < 0) {
            sets.push(lerpCrossing(samples[i - 1].frac, a0, samples[i].frac, a1))
        }
    }

    var moonrise = rises.length ? rises[0] : 0
    var moonset = sets.length ? sets[0] : 0
    var wraps = false

    if (rises.length && sets.length) {
        moonrise = rises[0]
        moonset = sets[0]
        wraps = moonrise > moonset
    } else if (rises.length && !sets.length) {
        moonrise = rises[0]
        moonset = 1
        wraps = false
    } else if (!rises.length && sets.length) {
        moonrise = 0
        moonset = sets[0]
        wraps = false
    } else {
        var upAll = samples[0].alt >= 0
        return {
            moonrise: 0,
            moonset: upAll ? 1 : 0,
            valid: true,
            wraps: false,
            up: upAll,
            alwaysUp: upAll,
            alwaysDown: !upAll
        }
    }

    var nowFrac = fractionOfLocalDay(day)
    return {
        moonrise: moonrise,
        moonset: moonset,
        valid: true,
        wraps: wraps,
        up: isUpInSpan(moonrise, moonset, nowFrac, wraps)
    }
}

function daySkyModel(date, latitude, longitude, businessStart, businessEnd) {
    var day = date || new Date()
    var sun = daySolarFractions(day, latitude, longitude)
    var moon = dayLunarFractions(day, latitude, longitude)
    var nowFrac = fractionOfLocalDay(day)
    var b0 = typeof businessStart === "number" ? businessStart : 8 / 24
    var b1 = typeof businessEnd === "number" ? businessEnd : 18 / 24
    return {
        valid: !!(sun.valid || moon.valid),
        now: nowFrac,
        sun: sun,
        moon: moon,
        work: {
            start: b0,
            end: b1,
            valid: b1 > b0,
            up: b1 > b0 && nowFrac >= b0 && nowFrac <= b1
        }
    }
}

/** Parabola point along rise→set. yNorm peaks at 1 in the middle. */
function arcPoint(rise, set, nowFrac, wraps) {
    if (wraps) {
        if (nowFrac >= rise) {
            var lenA = 1 - rise
            var lenB = set
            var total = lenA + lenB
            if (total <= 0) {
                return { visible: false, xFrac: nowFrac, yNorm: 0, t: 0 }
            }
            var t = (nowFrac - rise) / total
            return { visible: true, xFrac: nowFrac, yNorm: 4 * t * (1 - t), t: t }
        }
        if (nowFrac <= set) {
            var lenA2 = 1 - rise
            var total2 = lenA2 + set
            if (total2 <= 0) {
                return { visible: false, xFrac: nowFrac, yNorm: 0, t: 0 }
            }
            var t2 = (lenA2 + nowFrac) / total2
            return { visible: true, xFrac: nowFrac, yNorm: 4 * t2 * (1 - t2), t: t2 }
        }
        return { visible: false, xFrac: nowFrac, yNorm: 0, t: 0 }
    }
    if (!(set > rise) || nowFrac < rise || nowFrac > set) {
        return { visible: false, xFrac: nowFrac, yNorm: 0, t: 0 }
    }
    var t0 = (nowFrac - rise) / (set - rise)
    return { visible: true, xFrac: nowFrac, yNorm: 4 * t0 * (1 - t0), t: t0 }
}

function isUpInSpan(rise, set, nowFrac, wraps) {
    if (wraps) {
        return nowFrac >= rise || nowFrac <= set
    }
    return nowFrac >= rise && nowFrac <= set
}

function fractionOfLocalDay(day) {
    var d = day || new Date()
    var start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0)
    return Math.max(0, Math.min(1, (d.getTime() - start.getTime()) / 86400000))
}

function lerpCrossing(f0, a0, f1, a1) {
    var denom = (a1 - a0)
    if (Math.abs(denom) < 1e-9) {
        return f1
    }
    var u = -a0 / denom
    return f0 + (f1 - f0) * Math.max(0, Math.min(1, u))
}

/** Approximate geocentric moon altitude (degrees) at lat/lon for a Date. */
function moonAltitudeDeg(date, latDeg, lonDeg) {
    var d = (date.getTime() - Date.UTC(2000, 0, 1, 12, 0, 0)) / 86400000
    var L = norm360(218.316 + 13.176396 * d)
    var M = norm360(134.963 + 13.064993 * d)
    var F = norm360(93.272 + 13.229350 * d)
    var lonE = L + 6.289 * Math.sin(rad(M))
    var latE = 5.128 * Math.sin(rad(F))
    var eps = rad(23.439 - 0.0000004 * d)
    var lonEr = rad(lonE)
    var latEr = rad(latE)
    var y = Math.cos(latEr) * Math.sin(lonEr) * Math.cos(eps)
            - Math.sin(latEr) * Math.sin(eps)
    var x = Math.cos(latEr) * Math.cos(lonEr)
    var ra = Math.atan2(y, x)
    var dec = Math.asin(
        Math.sin(latEr) * Math.cos(eps)
        + Math.cos(latEr) * Math.sin(eps) * Math.sin(lonEr)
    )

    // Local sidereal time from GMST (degrees)
    var jd = (date.getTime() / 86400000) + 2440587.5
    var gmst = norm360(280.46061837 + 360.98564736629 * (jd - 2451545.0))
    var lst = norm360(gmst + lonDeg)
    var ha = rad(lst) - ra
    var lat = rad(latDeg)
    var alt = Math.asin(
        Math.sin(lat) * Math.sin(dec)
        + Math.cos(lat) * Math.cos(dec) * Math.cos(ha)
    )
    return deg(alt)
}

function rad(d) {
    return d * Math.PI / 180
}

function deg(r) {
    return r * 180 / Math.PI
}

function norm360(v) {
    var x = v % 360
    return x < 0 ? x + 360 : x
}
