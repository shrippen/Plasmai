import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.dateandtime
import "../../contents/code/dateTimeFormat.js" as DTF
import "."
import "../Kante"

/**
 * Locale-formatted date field with click-to-select segments (day/month/year)
 * and a calendar popup.
 */
RowLayout {
    id: root

    /** Keep as JS Date (var). QML `date` type often lacks getTime() across item boundaries. */
    property var selectedDate: new Date()
    readonly property real selectedDateMs: {
        var d = DTF.coerceDate(selectedDate)
        return d ? d.getTime() : 0
    }
    /** Display text (locale short date). */
    property alias text: dateField.text

    readonly property var segmentRoles: DTF.dateSegmentRoles(DTF.localeDateFormat())

    signal dateEdited()

    property int activeSegment: -1
    property string digitBuffer: ""
    property bool suppressHandler: false

    function parseDate(text) {
        return DTF.parseLocaleDate(text)
    }

    function setDate(d) {
        var next = DTF.coerceDate(d)
        if (!next) {
            return
        }
        selectedDate = next
        suppressHandler = true
        dateField.text = DTF.formatLocaleDate(next)
        suppressHandler = false
        root.dateEdited()
    }

    function refreshText() {
        suppressHandler = true
        dateField.text = DTF.formatLocaleDate(selectedDate)
        suppressHandler = false
    }

    function selectSegment(index) {
        var segs = DTF.digitSegments(dateField.text)
        if (index < 0 || index >= segs.length) {
            activeSegment = -1
            digitBuffer = ""
            return
        }
        activeSegment = index
        digitBuffer = ""
        dateField.forceActiveFocus()
        dateField.select(segs[index].start, segs[index].end)
    }

    function selectSegmentAtCursor() {
        var idx = DTF.segmentAtCursor(dateField.text, dateField.cursorPosition)
        selectSegment(idx)
    }

    function applyDigit(digit) {
        var roles = root.segmentRoles
        if (activeSegment < 0 || activeSegment >= roles.length) {
            selectSegmentAtCursor()
        }
        if (activeSegment < 0) {
            return
        }
        var role = roles[activeSegment]
        var maxLen = DTF.segmentMaxLen(role, DTF.localeDateFormat())
        digitBuffer += digit
        if (digitBuffer.length > maxLen) {
            digitBuffer = digitBuffer.slice(-maxLen)
        }

        // Update live when we have a usable value
        var next = null
        var base = DTF.coerceDate(selectedDate) || new Date()
        if (role === "y") {
            // Only commit year when the field width is filled (yy or yyyy)
            if (digitBuffer.length >= maxLen) {
                next = DTF.applyDateSegment(base, roles, activeSegment, digitBuffer)
            }
        } else if (digitBuffer.length >= 1) {
            // For month/day allow 1–2 digits; clamp on each keystroke once non-empty
            next = DTF.applyDateSegment(base, roles, activeSegment, digitBuffer)
        }

        if (next && !isNaN(next.getTime())) {
            selectedDate = next
            refreshText()
        }

        if (digitBuffer.length >= maxLen) {
            var nextIdx = activeSegment + 1
            var lastIdx = activeSegment
            digitBuffer = ""
            Qt.callLater(function() {
                if (nextIdx < roles.length) {
                    selectSegment(nextIdx)
                } else {
                    selectSegment(lastIdx)
                }
            })
        } else if (next && !isNaN(next.getTime())) {
            var stay = activeSegment
            var buf = digitBuffer
            Qt.callLater(function() {
                selectSegment(stay)
                digitBuffer = buf
            })
        }
    }

    KanteTextField {
        id: dateField
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(implicitHeight, TouchUi.controlMinHeight)
        placeholderText: text.length > 0 ? "" : DTF.datePlaceholder()  // Material floats the placeholder above filled fields
        inputMethodHints: Qt.ImhDate | Qt.ImhPreferNumbers
        // Keep selection look when clicking segments
        selectByMouse: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.IBeamCursor
            propagateComposedEvents: true
            onPressed: function(mouse) {
                dateField.forceActiveFocus()
                var pos = dateField.positionAt(mouse.x, mouse.y, TextInput.CursorBetweenCharacters)
                dateField.cursorPosition = pos
                root.selectSegmentAtCursor()
                mouse.accepted = true
            }
            onDoubleClicked: function(mouse) {
                // Allow normal word select via double-click → still snap to segment
                root.selectSegmentAtCursor()
                mouse.accepted = true
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                return
            }
            if (event.key === Qt.Key_Left) {
                event.accepted = true
                root.selectSegment(Math.max(0, root.activeSegment - 1))
                return
            }
            if (event.key === Qt.Key_Right) {
                event.accepted = true
                root.selectSegment(Math.min(root.segmentRoles.length - 1, root.activeSegment + 1))
                return
            }
            if (event.text && event.text >= "0" && event.text <= "9") {
                event.accepted = true
                root.applyDigit(event.text)
                return
            }
            // Block free-form edits that break locale structure; allow Delete to reset segment
            if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                event.accepted = true
                root.digitBuffer = ""
                root.selectSegment(root.activeSegment >= 0 ? root.activeSegment : 0)
            }
        }

        onEditingFinished: {
            var d = root.parseDate(text)
            if (d) {
                root.setDate(d)
            } else {
                root.refreshText()
            }
            root.activeSegment = -1
            root.digitBuffer = ""
        }
    }

    /** Opens the calendar popup programmatically (e.g. from a custom big-text header). */
    function openPicker() {
        calendarLoader.active = true
        calendarLoader.item.value = DTF.coerceDate(root.selectedDate) || new Date()
        calendarLoader.item.open()
    }

    KanteToolButton {
        Layout.preferredWidth: TouchUi.active ? TouchUi.buttonMinHeight : implicitWidth
        Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
        icon.name: "view-calendar"
        text: i18n("Pick date")
        display: QQC2.AbstractButton.IconOnly
        enabled: dateField.enabled
        onClicked: root.openPicker()
        QQC2.ToolTip.text: text
        QQC2.ToolTip.visible: hovered && !Kirigami.Settings.isMobile
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // The calendar popup builds several month/year/decade views; create it on first use only,
    // otherwise every DateField slows down the page it sits on.
    Loader {
        id: calendarLoader
        active: false
        sourceComponent: DatePopup {
            parent: QQC2.Overlay.overlay
            anchors.centerIn: parent
            onAccepted: root.setDate(new Date(value.getFullYear(), value.getMonth(), value.getDate(), 12, 0, 0, 0))
        }
    }

    Component.onCompleted: refreshText()
}
