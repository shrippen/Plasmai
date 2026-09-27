.pragma library

/**
 * Trip map: OpenStreetMap tiles (Web Mercator) around a trip's start and
 * destination, so a wrong place stands out. Pure math; TripMap.qml draws it.
 */

var TILE = 256
var TILE_URL = "https://tile.openstreetmap.org/"
var EARTH_KM = 6371

function rad(deg) {
    return deg * Math.PI / 180
}

/** Great-circle distance in km. */
function distanceKm(a, b) {
    var dLat = rad(b.latitude - a.latitude)
    var dLon = rad(b.longitude - a.longitude)
    var h = Math.sin(dLat / 2) * Math.sin(dLat / 2)
        + Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
    return 2 * EARTH_KM * Math.asin(Math.min(1, Math.sqrt(h)))
}

/** Position on the whole map at zoom z, in pixels. */
function worldPixel(p, z) {
    var size = TILE * Math.pow(2, z)
    var s = Math.sin(rad(Math.max(-85, Math.min(85, p.latitude))))
    return {
        x: (p.longitude + 180) / 360 * size,
        y: (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * size
    }
}

/**
 * The closest zoom (up to maxZoom) that shows all points inside width×height
 * with `margin` px around them; the view is centred on them.
 * { zoom, left, top, width, height } (left/top: world pixels of the view's corner).
 */
function fitView(points, width, height, margin, maxZoom) {
    var zoom = maxZoom
    for (; zoom > 0; zoom--) {
        var box = bounds(points, zoom)
        if (box.right - box.left <= width - 2 * margin && box.bottom - box.top <= height - 2 * margin) {
            break
        }
    }
    var b = bounds(points, zoom)
    return {
        zoom: zoom,
        left: (b.left + b.right) / 2 - width / 2,
        top: (b.top + b.bottom) / 2 - height / 2,
        width: width,
        height: height
    }
}

function bounds(points, zoom) {
    var box = { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity }
    for (var i = 0; i < points.length; i++) {
        var p = worldPixel(points[i], zoom)
        box.left = Math.min(box.left, p.x)
        box.right = Math.max(box.right, p.x)
        box.top = Math.min(box.top, p.y)
        box.bottom = Math.max(box.bottom, p.y)
    }
    return box
}

/** A point's position inside the view. */
function toView(p, view) {
    var w = worldPixel(p, view.zoom)
    return { x: w.x - view.left, y: w.y - view.top }
}

/** Tiles covering the view: [{ url, x, y }] with x/y inside the view. */
function tiles(view) {
    var count = Math.pow(2, view.zoom)
    var out = []
    var x0 = Math.floor(view.left / TILE)
    var y0 = Math.floor(view.top / TILE)
    var x1 = Math.floor((view.left + view.width - 1) / TILE)
    var y1 = Math.floor((view.top + view.height - 1) / TILE)
    for (var ty = y0; ty <= y1; ty++) {
        if (ty < 0 || ty >= count) {
            continue
        }
        for (var tx = x0; tx <= x1; tx++) {
            var wrapped = ((tx % count) + count) % count
            out.push({ url: TILE_URL + view.zoom + "/" + wrapped + "/" + ty + ".png",
                       x: tx * TILE - view.left, y: ty * TILE - view.top })
        }
    }
    return out
}

/** The route between both points on openstreetmap.org (to check the km). */
function routeUrl(a, b) {
    return "https://www.openstreetmap.org/directions?route="
        + encodeURIComponent(a.latitude + "," + a.longitude + ";" + b.latitude + "," + b.longitude)
}

/**
 * Entered one-way km against the straight line:
 * "shorter" (impossible), "longer" (more than 3× and 20 km: likely a wrong place), "ok", or "" without km.
 */
function checkDistance(straightKm, enteredKm) {
    if (isNaN(enteredKm) || enteredKm <= 0 || isNaN(straightKm)) {
        return ""
    }
    if (enteredKm < straightKm * 0.95) {
        return "shorter"
    }
    if (enteredKm > straightKm * 3 && enteredKm - straightKm > 20) {
        return "longer"
    }
    return "ok"
}

/** "50.95670, 11.06017" → { displayName, latitude, longitude }; null for anything else. */
function parseCoordinates(text) {
    var m = /^\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*$/.exec(String(text || ""))
    if (!m) {
        return null
    }
    var lat = Number(m[1])
    var lon = Number(m[2])
    if (Math.abs(lat) > 90 || Math.abs(lon) > 180) {
        return null
    }
    return { displayName: String(text).trim(), latitude: lat, longitude: lon }
}
