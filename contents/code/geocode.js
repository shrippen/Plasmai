.pragma library

/**
 * OpenStreetMap Nominatim geocoding (city / place search).
 * Requires a descriptive User-Agent per Nominatim usage policy.
 */
var USER_AGENT = "Plasmai/0.5.0 (https://github.com/shrippen/Plasmai)"
var SEARCH_URL = "https://nominatim.openstreetmap.org/search"

function search(query, callback) {
    var q = String(query || "").trim()
    if (!q) {
        callback({ ok: false, error: "empty", results: [] })
        return
    }

    var url = SEARCH_URL
        + "?format=json"
        + "&addressdetails=0"
        + "&limit=8"
        + "&q=" + encodeURIComponent(q)

    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) {
            return
        }
        if (xhr.status !== 200) {
            callback({ ok: false, error: "http", status: xhr.status, results: [] })
            return
        }
        var raw = []
        try {
            raw = JSON.parse(xhr.responseText) || []
        } catch (e) {
            callback({ ok: false, error: "parse", results: [] })
            return
        }
        var results = []
        for (var i = 0; i < raw.length; i++) {
            var row = raw[i]
            if (!row) {
                continue
            }
            var lat = parseFloat(row.lat)
            var lon = parseFloat(row.lon)
            if (isNaN(lat) || isNaN(lon)) {
                continue
            }
            results.push({
                displayName: row.display_name || (lat + ", " + lon),
                latitude: lat,
                longitude: lon
            })
        }
        callback({ ok: true, results: results })
    }
    xhr.open("GET", url)
    xhr.setRequestHeader("Accept", "application/json")
    xhr.setRequestHeader("User-Agent", USER_AGENT)
    xhr.send()
}
