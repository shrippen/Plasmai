import QtQuick
import QtQuick.Controls as QQC2
import QtTest

// The app's time picker (kirigami-addons' TimePopup) must show the time it was
// opened for, every time: TimePicker only moves its minute tumbler on creation.
TestCase {
    name: "AppTimePicker"
    when: windowShown
    width: 400
    height: 400

    Component {
        id: pickerComponent
        Loader { source: Qt.resolvedUrl("../../app/qml/controls/TimePicker.qml") }
    }

    // The Tumbler with `count` entries below `item` (24 = hours, 60 = minutes).
    function tumbler(item, count) {
        if (!item) {
            return null
        }
        if (item instanceof QQC2.Tumbler && item.count === count) {
            return item
        }
        var kids = item.children || []
        for (var i = 0; i < kids.length; ++i) {
            var found = tumbler(kids[i], count)
            if (found) {
                return found
            }
        }
        return null
    }

    function shownTime(picker, hours, minutes) {
        picker.openFor(hours, minutes)
        var popup = picker.children[0].item
        tryCompare(popup, "opened", true)
        var shown = [tumbler(popup.contentItem, 24).currentIndex, tumbler(popup.contentItem, 60).currentIndex]
        popup.close()
        tryCompare(popup, "visible", false)
        return shown
    }

    function test_showsRequestedTime() {
        var loader = createTemporaryObject(pickerComponent, this)
        tryCompare(loader, "status", Loader.Ready)
        compare(shownTime(loader.item, 9, 30), [9, 30])
        compare(shownTime(loader.item, 14, 5), [14, 5])
    }
}
