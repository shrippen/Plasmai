import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigamiaddons.dateandtime

// The app's time picker for TimeField (see DatePicker.qml): kirigami-addons' TimePopup.
// openFor(hours, minutes) shows it, picked(hours, minutes) reports the choice.
Item {
    id: picker

    // The time the next popup starts at.
    property date initial: new Date()

    signal picked(int hours, int minutes)

    // A fresh popup per open: TimePicker only moves its minute tumbler on creation,
    // a reused one would show the previous minutes.
    function openFor(hours, minutes) {
        var value = new Date()
        value.setHours(hours, minutes, 0, 0)
        picker.initial = value
        loader.active = false
        loader.active = true
        loader.item.open()
    }

    visible: false

    Loader {
        id: loader
        active: false
        sourceComponent: TimePopup {
            parent: QQC2.Overlay.overlay
            anchors.centerIn: parent
            value: picker.initial
            onAccepted: picker.picked(value.getHours(), value.getMinutes())
        }
    }
}
