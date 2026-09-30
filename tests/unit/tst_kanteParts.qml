import QtQuick
import QtTest
import "../../contents/ui"
import "../../contents/ui/Kante"

// Kante builds tag chips from KanteChip; System keeps its own pills.
TestCase {
    name: "KanteParts"
    visible: true
    when: windowShown
    width: 400
    height: 300

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
}
