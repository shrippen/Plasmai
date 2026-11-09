import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../app/qml"

/** LazyDialog (app/qml): the dialog is built when first opened, once, with the values handed over. */
TestCase {
    id: tc
    name: "LazyDialog"
    width: 300
    height: 300
    when: windowShown

    property int built: 0

    Component {
        id: scene
        LazyDialog {
            sourceComponent: Component {
                QQC2.Dialog {
                    property var target: null
                    width: 100
                    height: 100
                    Component.onCompleted: tc.built++
                }
            }
        }
    }

    function init() {
        built = 0
    }

    function test_nothing_is_built_before_it_opens() {
        const lazy = createTemporaryObject(scene, tc)
        compare(built, 0)
        compare(lazy.item, null)
    }

    function test_open_builds_once_sets_the_values_and_opens() {
        const lazy = createTemporaryObject(scene, tc)
        lazy.open({ target: "entry 7" })
        compare(built, 1)
        compare(lazy.item.target, "entry 7")
        tryVerify(function() { return lazy.item.opened })
        lazy.item.close()
        tryVerify(function() { return !lazy.item.visible })
        lazy.open({ target: "entry 8" })
        compare(built, 1, "opened again: the same dialog")
        compare(lazy.item.target, "entry 8")
    }

    function test_build_hands_out_the_dialog_without_opening_it() {
        const lazy = createTemporaryObject(scene, tc)
        const dialog = lazy.build()
        verify(dialog !== null)
        verify(!dialog.visible)
        compare(lazy.build(), dialog)
        compare(built, 1)
    }
}
