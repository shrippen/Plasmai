.pragma library

/**
 * Approximate local-time sunrise/sunset as fractions of a 24h day [0, 1].
 * Based on the NOAA solar calculation (zenith 90.833°).
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

    // Day of year
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
            // Sun never rises
            return isSunrise ? null : 24
        }
        if (cosH < -1) {
            // Sun never sets
            return isSunrise ? 0 : null
        }

        var h = isSunrise
            ? 360 - deg(Math.acos(cosH))
            : deg(Math.acos(cosH))
        h = h / 15
        var localT = h + ra - (0.06571 * t) - 6.622
        var ut = localT - lngHour
        ut = ((ut % 24) + 24) % 24

        // Convert UT to local civil time using the Date's timezone offset.
        var offsetHours = -day.getTimezoneOffset() / 60
        var local = ut + offsetHours
        local = ((local % 24) + 24) % 24
        return local
    }

    var rise = eventHours(true)
    var set = eventHours(false)

    if (rise === null && set === 24) {
        // Polar night
        return { sunrise: 0, sunset: 0, valid: true, polarNight: true }
    }
    if (rise === 0 && set === null) {
        // Midnight sun
        return { sunrise: 0, sunset: 1, valid: true, polarDay: true }
    }

    var sunrise = (typeof rise === "number") ? rise / 24 : 6 / 24
    var sunset = (typeof set === "number") ? set / 24 : 18 / 24
    if (sunset <= sunrise) {
        // Shouldn't happen often; keep a minimal day band.
        sunset = Math.min(1, sunrise + 1 / 24)
    }
    return { sunrise: sunrise, sunset: sunset, valid: true }
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
