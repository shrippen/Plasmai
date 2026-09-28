import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../contents/ui/Kante"

// A skin inside a Kirigami.Dialog must not count as content: the dialog's
// ScrollView sizes itself only from a single content item, a second one
// left the form (fields, buttons) at height 0.
TestCase {
    name: "KanteDialogSkin"
    when: windowShown
    width: 400
    height: 400

    Component {
        id: dialogComponent
        Kirigami.Dialog {
            id: dialog
            KanteDialogSkin { dialog: dialog }
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
