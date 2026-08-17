import QtQuick
import QtTest
import "../../contents/code/colorDistinct.js" as ColorDistinct

TestCase {
    name: "ColorDistinct"

    function init() {
        ColorDistinct.invalidateCache()
        ColorDistinct.configure(true, 22)
        ColorDistinct.setThemePalette(["#3584e4", "#33d17a", "#f66151"])
    }

    function test_normalizeHex() {
        compare(ColorDistinct.normalizeHex("AABBCC"), "#aabbcc")
        compare(ColorDistinct.normalizeHex("#abc"), "#aabbcc")
        compare(ColorDistinct.normalizeHex("  #Ff00Aa  "), "#ff00aa")
    }

    function test_similarColorsShiftWithinCategory() {
        var customers = [
            { id: 1, name: "A", color: "#3584e4" },
            { id: 2, name: "B", color: "#3584e4" },
            { id: 3, name: "C", color: "#33d17a" }
        ]
        ColorDistinct.rebuild(customers, [], [], true)
        var c1 = ColorDistinct.adjust("customer", 1, "#3584e4")
        var c2 = ColorDistinct.adjust("customer", 2, "#3584e4")
        verify(c1 !== c2)
        var groups = ColorDistinct.maintenanceGroups("customer", customers)
        verify(groups.length >= 1)
        var shifted = 0
        for (var g = 0; g < groups.length; g++) {
            var entries = groups[g].entries || []
            for (var i = 0; i < entries.length; i++) {
                if (entries[i].shifted) {
                    shifted++
                }
            }
        }
        verify(shifted >= 1)
    }

    function test_rebuildCacheSkip() {
        var customers = [{ id: 1, color: "#3584e4" }]
        verify(ColorDistinct.rebuild(customers, [], [], true))
        verify(!ColorDistinct.rebuild(customers, [], [], false))
        verify(ColorDistinct.rebuild(customers, [], [], true))
    }

    function test_disabledCopiesOriginals() {
        ColorDistinct.configure(false, 22)
        var customers = [
            { id: 1, color: "#3584e4" },
            { id: 2, color: "#3584e4" }
        ]
        ColorDistinct.rebuild(customers, [], [], true)
        compare(ColorDistinct.adjust("customer", 1, "#3584e4"), ColorDistinct.normalizeHex("#3584e4"))
        compare(ColorDistinct.adjust("customer", 2, "#3584e4"), ColorDistinct.normalizeHex("#3584e4"))
        compare(ColorDistinct.maintenanceGroups("customer", customers).length, 0)
    }

    function test_flattenActivitiesByProject() {
        var flat = ColorDistinct.flattenActivitiesByProject(
            { "1": [{ id: 10 }], "2": [{ id: 11 }] },
            [{ id: 10 }, { id: 12 }]
        )
        compare(flat.length, 3)
    }

    function test_colorDistanceZeroForSame() {
        compare(ColorDistinct.colorDistancePercent("#ffffff", "#FFFFFF"), 0)
        verify(ColorDistinct.colorDistancePercent("#000000", "#ffffff") > 50)
    }
}
