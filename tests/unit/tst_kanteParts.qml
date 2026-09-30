import QtQuick
import QtTest
import "../../contents/ui"
import "../../contents/ui/Kante"

// Kante builds tag chips and the offline note from Kante components
// (KanteChip, KanteCallout); System keeps its own pills and row.
TestCase {
    name: "KanteParts"
    visible: true
    when: windowShown
    width: 400
    height: 300

    SignalSpy {
        id: detailsSpy
        signalName: "detailsRequested"
    }

    readonly property var tags: [{ name: "urgent", color: "#cc241d" }]

    function cleanup() {
        KanteStyle.kind = KanteStyle.Kind.System
    }

    function findTagDelegate(item) {
        if (item.hasOwnProperty("pillColor")) {
            return item
        }
        for (var i = 0; i < item.children.length; i++) {
            var found = findTagDelegate(item.children[i])
            if (found) {
                return found
            }
        }
        return null
    }

    function findItem(item, test) {
        if (test(item)) {
            return item
        }
        for (var i = 0; i < item.children.length; i++) {
            var found = findItem(item.children[i], test)
            if (found) {
                return found
            }
        }
        return null
    }

    // Trip map pins: Kante squares in the map marker role; System round accent dots.
    function test_tripMapPins_data() {
        return [
            { tag: "system", kind: KanteStyle.Kind.System, kante: false },
            { tag: "kante", kind: KanteStyle.Kind.Kante, kante: true },
            { tag: "kanteLight", kind: KanteStyle.Kind.KanteLight, kante: true }
        ]
    }

    function test_tripMapPins(data) {
        KanteStyle.kind = data.kind
        var map = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/TripMap.qml")), this, { width: 300 })
        verify(map !== null)
        var pin = findItem(map, function(i) { return i.modelData !== undefined && i.modelData.label === "A" })
        verify(pin !== null)
        compare(pin.radius === 0, data.kante)
        compare(pin.color, data.kante ? KanteStyle.mapMarkerColor : KanteStyle.accentColor)
    }

    // Recent entries: Kante draws a KanteListRow (time, swatch, two lines, duration).
    function test_activityLine_data() {
        return [
            { tag: "system", kind: KanteStyle.Kind.System, kante: false },
            { tag: "kante", kind: KanteStyle.Kind.Kante, kante: true },
            { tag: "kanteLight", kind: KanteStyle.Kind.KanteLight, kante: true }
        ]
    }

    function test_activityLine(data) {
        KanteStyle.kind = data.kind
        var row = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/ActivityListRow.qml")), this,
                                        { width: 300, titleText: "Design", subtitleText: "ACME · Web",
                                          timeText: "07:42", durationText: "1:05", customerColor: "#458588" })
        verify(row !== null)
        var line = findItem(row, function(i) { return i.leadingText !== undefined })
        verify(line !== null)
        compare(line.visible, data.kante)
        compare(line.leadingText, "07:42")
        compare(line.text, "Design")
        compare(line.subtitle, "ACME · Web")
        compare(line.meta, "1:05")
        verify(!line.activeFocusOnTab)
        if (data.kante) {
            verify(row.implicitHeight >= line.implicitHeight)
        }

        row.runningHintVisible = true
        compare(line.meta, "")
    }

    function stamp(h, m) {
        var d = new Date()
        d.setHours(h, m, 0, 0)
        return d.toISOString()
    }

    // Day strip: Kimai entries become KanteDayStrip segments in hours, the work day
    // the work band, the location daylight.
    function test_entryDayStrip() {
        KanteStyle.kind = KanteStyle.Kind.Kante
        var strip = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/EntryDayStrip.qml")), this, {
            width: 300, workDayBegin: "08:30", workDayEnd: "17:00",
            customersById: { 1: { id: 1, color: "#d65d0e" } },
            entries: [{ begin: stamp(8, 15), end: stamp(9, 45), project: { customer: 1 } },
                      { begin: stamp(10, 0), end: null }]
        })
        verify(strip !== null)
        compare(strip.segments.length, 2)
        compare(strip.segments[0].from, 8.25)
        compare(strip.segments[0].to, 9.75)
        verify(strip.segments[0].color !== undefined)
        compare(strip.segments[1].color, undefined)
        compare(strip.workFrom, 8.5)
        compare(strip.workTo, 17)
        compare(strip.spanFrom, 8)
        compare(strip.sunrise, -1)

        strip.latitude = 52.52
        strip.longitude = 13.405
        verify(strip.sunrise > 0)
        verify(strip.sunset > strip.sunrise)
    }

    // Tags: Kante shows a KanteTagPicker (chips + search), System its own pills.
    function test_tagPicker_data() {
        return [
            { tag: "system", kind: KanteStyle.Kind.System, kante: false },
            { tag: "kante", kind: KanteStyle.Kind.Kante, kante: true },
            { tag: "kanteLight", kind: KanteStyle.Kind.KanteLight, kante: true }
        ]
    }

    function test_tagPicker(data) {
        KanteStyle.kind = data.kind
        var picker = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/TagPicker.qml")), this,
                                           { width: 300, selectedTagEntries: tags })
        verify(picker !== null)
        var kante = findItem(picker, function(i) { return i.tagNames !== undefined })
        var chrome = findTagDelegate(picker)
        while (chrome.parent !== picker) {
            chrome = chrome.parent
        }
        compare(kante.visible, data.kante)
        compare(chrome.visible, !data.kante)
        compare(kante.tagNames, ["urgent"])
    }

    // Edits in the Kante picker come back as {name, color} entries.
    function test_tagPickerEdits() {
        KanteStyle.kind = KanteStyle.Kind.Kante
        var picker = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/TagPicker.qml")), this,
                                           { width: 300, selectedTagEntries: tags })
        var kante = findItem(picker, function(i) { return i.tagNames !== undefined })
        kante.add("meeting")
        compare(picker.selectedTagEntries.length, 2)
        compare(picker.selectedTagEntries[1].name, "meeting")
        verify(picker.selectedTagEntries[1].color !== undefined)
        compare(picker.normalizedTags, ["urgent", "meeting"])

        kante.remove(0)
        compare(picker.normalizedTags, ["meeting"])
    }

    function test_offlineStatus_data() {
        return [
            { tag: "system", kind: KanteStyle.Kind.System, callout: false },
            { tag: "kante", kind: KanteStyle.Kind.Kante, callout: true },
            { tag: "kanteLight", kind: KanteStyle.Kind.KanteLight, callout: true }
        ]
    }

    function test_offlineStatus(data) {
        KanteStyle.kind = data.kind
        var status = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/OfflineStatus.qml")), this,
                                           { width: 300, unsynced: 2 })
        verify(status !== null)
        verify(status.visible)
        var callout = status.children[0]
        var row = status.children[1]
        compare(callout.visible, data.callout)
        compare(row.visible, !data.callout)
        compare(callout.kind, KanteCallout.Kind.Info)
        compare(status.implicitHeight, data.callout ? callout.implicitHeight : row.implicitHeight)

        status.stuck = 1
        compare(callout.kind, KanteCallout.Kind.Warn)
    }

    // "Show" is the callout's action and opens the waiting changes.
    function test_offlineShowAction() {
        KanteStyle.kind = KanteStyle.Kind.Kante
        var status = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/OfflineStatus.qml")), this,
                                           { width: 300, unsynced: 2 })
        detailsSpy.clear()
        detailsSpy.target = status
        var show = status.children[0].actions[0]
        verify(show.visible)
        show.clicked()
        compare(detailsSpy.count, 1)

        status.showDetails = false
        verify(!show.visible)
    }
}
