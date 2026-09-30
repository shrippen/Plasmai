import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../contents/ui/Kante"

// Kante 1.4's skin is an Item: as a child of a Kirigami.Dialog it counts as
// content, and the dialog's ScrollView sizes itself only from a single content
// item, so the form (fields, buttons) got height 0. Call sites hold the skin
// in a property instead.
TestCase {
    name: "KanteDialogSkin"
    when: windowShown
    width: 400
    height: 400

    Component {
        id: dialogComponent
        Kirigami.Dialog {
            id: dialog
            readonly property QtObject kanteSkin: KanteDialogSkin { dialog: dialog }
            Rectangle { implicitWidth: 100; implicitHeight: 80 }
        }
    }

    function test_formKeepsItsHeight() {
        var d = createTemporaryObject(dialogComponent, this)
        d.open()
        tryCompare(d, "opened", true)
        verify(d.contentItem.implicitHeight >= 80, "content height " + d.contentItem.implicitHeight)
    }
}
