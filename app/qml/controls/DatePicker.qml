import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigamiaddons.dateandtime

// The app's date picker for DateField (see Button.qml): kirigami-addons' DatePopup,
// centered, touch-friendly. Same API as the Plasmoid's calendar popup:
// openFor(date) shows it, picked(date) reports the day (noon, local time).
// It builds several month/year/decade views, so it is created on first use only.
Item {
    id: picker

    signal picked(var date)

    function openFor(date) {
        loader.active = true
        loader.item.value = date
        loader.item.open()
    }

    visible: false

    Loader {
        id: loader
        active: false
        sourceComponent: DatePopup {
            parent: QQC2.Overlay.overlay
            anchors.centerIn: parent
            onAccepted: picker.picked(new Date(value.getFullYear(), value.getMonth(), value.getDate(), 12, 0, 0, 0))
        }
    }
}
