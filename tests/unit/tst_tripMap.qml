import QtQuick
import QtTest
import "../../contents/code/tripMap.js" as TripMap

TestCase {
    name: "TripMap"

    readonly property var hamburg: ({ latitude: 53.5511, longitude: 9.9937 })
    readonly property var luebeck: ({ latitude: 53.8655, longitude: 10.6866 })

    function test_distanceKm() {
        var km = TripMap.distanceKm(hamburg, luebeck)
        verify(km > 55 && km < 58, km)
        compare(TripMap.distanceKm(hamburg, hamburg), 0)
    }

    function test_worldPixel() {
        // Zoom 0: the world is one 256 px tile; lon 0 / lat 0 is its centre.
        var p = TripMap.worldPixel({ latitude: 0, longitude: 0 }, 0)
        compare(Math.round(p.x), 128)
        compare(Math.round(p.y), 128)
    }

    // Both points fit with a margin, at the closest zoom that allows it.
    function test_fitView() {
        var v = TripMap.fitView([hamburg, luebeck], 360, 200, 32, 16)
        verify(v.zoom >= 7 && v.zoom <= 10, v.zoom)
        var a = TripMap.toView(hamburg, v)
        var b = TripMap.toView(luebeck, v)
        verify(a.x >= 32 && a.x <= 328 && b.x >= 32 && b.x <= 328, a.x + " " + b.x)
        verify(a.y >= 32 && a.y <= 168 && b.y >= 32 && b.y <= 168, a.y + " " + b.y)
        // one point: a city-level zoom around it
        var one = TripMap.fitView([hamburg], 360, 200, 32, 14)
        compare(one.zoom, 14)
        var c = TripMap.toView(hamburg, one)
        compare(Math.round(c.x), 180)
        compare(Math.round(c.y), 100)
    }

    // The tiles that cover the view, with their place in it.
    function test_tiles() {
        var v = TripMap.fitView([hamburg, luebeck], 360, 200, 32, 16)
        var tiles = TripMap.tiles(v)
        verify(tiles.length >= 2 && tiles.length <= 9, tiles.length)
        for (var i = 0; i < tiles.length; i++) {
            verify(tiles[i].url.indexOf("https://tile.openstreetmap.org/" + v.zoom + "/") === 0, tiles[i].url)
            verify(tiles[i].x > -256 && tiles[i].x < 360)
            verify(tiles[i].y > -256 && tiles[i].y < 200)
        }
    }

    function test_routeUrl() {
        compare(TripMap.routeUrl(hamburg, luebeck),
                "https://www.openstreetmap.org/directions?route=53.5511%2C9.9937%3B53.8655%2C10.6866")
    }

    // The entered one-way km against the straight line: shorter is impossible,
    // far longer usually means a wrong place.
    function test_checkDistance() {
        compare(TripMap.checkDistance(57, 70), "ok")
        compare(TripMap.checkDistance(57, 40), "shorter")
        compare(TripMap.checkDistance(57, 250), "longer")
        compare(TripMap.checkDistance(57, NaN), "")
    }

    // Dawarich suggestions name places by coordinates: those need no search.
    function test_parseCoordinates() {
        var p = TripMap.parseCoordinates("50.95670, 11.06017")
        compare(p.latitude, 50.9567)
        compare(p.longitude, 11.06017)
        verify(TripMap.parseCoordinates("-33.9,151.2") !== null)
        compare(TripMap.parseCoordinates("Weimar, 99428 Weimar"), null)
        compare(TripMap.parseCoordinates("95.0, 11.0"), null)
    }
}
