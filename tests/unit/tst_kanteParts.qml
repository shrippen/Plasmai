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

    function test_tagChip_data() {
        return [
            { tag: "system", kind: KanteStyle.Kind.System, chip: false },
            { tag: "kante", kind: KanteStyle.Kind.Kante, chip: true },
            { tag: "kanteLight", kind: KanteStyle.Kind.KanteLight, chip: true }
        ]
    }

    function test_tagChip(data) {
        KanteStyle.kind = data.kind
        var picker = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/TagPicker.qml")), this,
                                           { width: 300, selectedTagEntries: tags })
        verify(picker !== null)
        var tag = findTagDelegate(picker)
        verify(tag !== null)
        var chip = tag.children[0]
        var pill = tag.children[1]
        compare(chip.visible, data.chip)
        compare(pill.visible, !data.chip)
        compare(chip.text, "urgent")
        compare(chip.chipColor, Qt.color("#cc241d"))
        verify(chip.removable)
        compare(tag.implicitWidth, data.chip ? chip.implicitWidth : pill.implicitWidth)
    }

    // The chip's cross removes the tag from the picker.
    function test_tagChipRemoves() {
        KanteStyle.kind = KanteStyle.Kind.Kante
        var picker = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/TagPicker.qml")), this,
                                           { width: 300, selectedTagEntries: tags })
        findTagDelegate(picker).children[0].removeRequested()
        compare(picker.selectedTagEntries.length, 0)
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
