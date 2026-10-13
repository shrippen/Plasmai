import QtQuick
import QtQuick.Controls as QQC2
import QtTest

// The app's time picker (kirigami-addons' TimePopup) must show the time it was
// opened for, every time: TimePicker only moves its minute tumbler on creation.
//
// The vendored TimePopup (app/addons/README.md) is loaded by file: in the app it wins
// from qrc, here an installed kirigami-addons compiled into its plugin would win over
// any import path. pickerComponent does what app/qml/controls/TimePicker.qml does.
TestCase {
    name: "AppTimePicker"
    when: windowShown
    width: 400
    height: 400

    readonly property url vendoredPopup: Qt.resolvedUrl("../../app/qml/kirigami-addons/org/kde/kirigamiaddons/dateandtime/TimePopup.qml")

    Component {
        id: pickerComponent
        Loader { sourceComponent: harness }
    }

    // openFor(hours, minutes) and picked(hours, minutes) as in controls/TimePicker.qml.
    Component {
        id: harness
        Item {
            id: picker
            signal picked(int hours, int minutes)

            function openFor(hours, minutes) {
                var value = new Date()
                value.setHours(hours, minutes, 0, 0)
                popupLoader.setSource(vendoredPopup, { value: value, parent: QQC2.Overlay.overlay })
                popupLoader.item.open()
            }

            Loader { id: popupLoader }

            Connections {
                target: popupLoader.item
                function onAccepted() {
                    picker.picked(popupLoader.item.value.getHours(), popupLoader.item.value.getMinutes())
                }
            }
        }
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

    // 12-hour locales ("h:mm AP"): an hour tumbler of 12 and an AM / PM tumbler.
    readonly property bool twelveHour: /a/i.test(Qt.locale().timeFormat(Locale.ShortFormat))

    SignalSpy {
        id: pickedSpy
        signalName: "picked"
    }

    // Opens the picker for a time, reads the tumblers, presses Select without a change.
    // Returns [shown hour index, shown minute, AM/PM index or -1, picked hours, picked minutes].
    function openAndSelect(picker, hours, minutes) {
        pickedSpy.target = picker
        pickedSpy.clear()
        picker.openFor(hours, minutes)
        var popup = picker.children[0].item
        tryCompare(popup, "opened", true)
        var hourTumbler = tumbler(popup.contentItem, twelveHour ? 12 : 24)
        verify(hourTumbler !== null, Qt.locale().name + ": hour tumbler")
        var amPm = twelveHour ? tumbler(popup.contentItem, 2) : null
        var shown = [hourTumbler.currentIndex, tumbler(popup.contentItem, 60).currentIndex, amPm ? amPm.currentIndex : -1]
        var select = popup.footer.contentChildren.filter(function(b) { return b.QQC2.DialogButtonBox.buttonRole === QQC2.DialogButtonBox.AcceptRole })[0]
        verify(!!select, "Select button")
        select.clicked()
        tryCompare(pickedSpy, "count", 1)
        tryCompare(popup, "visible", false)
        var args = pickedSpy.signalArguments[0]
        return shown.concat([args[0], args[1]])
    }

    function test_showsAndKeepsRequestedTime_data() {
        return [
            { tag: "00:00", h: 0, m: 0 },
            { tag: "00:45", h: 0, m: 45 },
            { tag: "09:30", h: 9, m: 30 },
            { tag: "12:00", h: 12, m: 0 },
            { tag: "12:15", h: 12, m: 15 },
            { tag: "14:05", h: 14, m: 5 },
            { tag: "23:59", h: 23, m: 59 }
        ]
    }

    // Shown as the locale writes it (12 for midnight and noon in 12-hour locales),
    // and Select without a change gives back the same time.
    function test_showsAndKeepsRequestedTime(data) {
        var loader = createTemporaryObject(pickerComponent, this)
        tryCompare(loader, "status", Loader.Ready)
        var r = openAndSelect(loader.item, data.h, data.m)
        var hourIndex = twelveHour ? data.h % 12 : data.h
        var half = twelveHour ? (data.h >= 12 ? 1 : 0) : -1
        compare(r.slice(0, 3), [hourIndex, data.m, half], Qt.locale().name + " shown")
        compare(r.slice(3), [data.h, data.m], Qt.locale().name + " picked")
    }

    // A changed minute (and in 12-hour locales the other half of the day) is what Select gives back.
    function test_changedTimeIsPicked() {
        var loader = createTemporaryObject(pickerComponent, this)
        tryCompare(loader, "status", Loader.Ready)
        var picker = loader.item
        pickedSpy.target = picker
        pickedSpy.clear()
        picker.openFor(12, 30)
        var popup = picker.children[0].item
        tryCompare(popup, "opened", true)
        tumbler(popup.contentItem, 60).currentIndex = 7
        if (twelveHour)
            tumbler(popup.contentItem, 2).currentIndex = 0
        var select = popup.footer.contentChildren.filter(function(b) { return b.QQC2.DialogButtonBox.buttonRole === QQC2.DialogButtonBox.AcceptRole })[0]
        select.clicked()
        tryCompare(pickedSpy, "count", 1)
        var args = pickedSpy.signalArguments[0]
        compare([args[0], args[1]], twelveHour ? [0, 7] : [12, 7], Qt.locale().name)
    }
}
