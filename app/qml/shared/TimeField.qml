import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.dateandtime
import "../../contents/code/dateTimeFormat.js" as DTF
import "."

/**
 * Locale-formatted time field with click-to-select segments (hour/minute)
 * and a tumbler popup.
 */
RowLayout {
    id: root

    property alias enabled: timeField.enabled
    property alias text: timeField.text
    property int hours: 0
    property int minutes: 0

    readonly property var segmentRoles: DTF.timeSegmentRoles(DTF.localeTimeFormat())

    signal timeEdited()

    property int activeSegment: -1
    property string digitBuffer: ""
    property bool suppressHandler: false

    function parseTime(text) {
        return DTF.parseLocaleTime(text)
    }

    function setTime(h, m) {
        hours = Math.max(0, Math.min(23, h))
        minutes = Math.max(0, Math.min(59, m))
        suppressHandler = true
        timeField.text = DTF.formatLocaleTime(hours, minutes)
        suppressHandler = false
        root.timeEdited()
    }

    function refreshText() {
        suppressHandler = true
        timeField.text = DTF.formatLocaleTime(hours, minutes)
        suppressHandler = false
    }

    function selectSegment(index) {
        var segs = DTF.digitSegments(timeField.text)
        // Ignore non H/m digit runs (e.g. nothing); map to role count
        if (index < 0 || index >= segs.length) {
            activeSegment = -1
            digitBuffer = ""
            return
        }
        activeSegment = index
        digitBuffer = ""
        timeField.forceActiveFocus()
        timeField.select(segs[index].start, segs[index].end)
    }

    function selectSegmentAtCursor() {
        var idx = DTF.segmentAtCursor(timeField.text, timeField.cursorPosition)
        // Only first roles.length digit segments are hour/minute
        var max = Math.min(root.segmentRoles.length, DTF.digitSegments(timeField.text).length)
        if (idx >= max) {
            idx = max - 1
        }
        selectSegment(idx)
    }

    function applyDigit(digit) {
        var roles = root.segmentRoles
        if (activeSegment < 0 || activeSegment >= roles.length) {
            selectSegmentAtCursor()
        }
        if (activeSegment < 0 || activeSegment >= roles.length) {
            return
        }
        var role = roles[activeSegment]
        var maxLen = DTF.segmentMaxLen(role)
        digitBuffer += digit
        if (digitBuffer.length > maxLen) {
            digitBuffer = digitBuffer.slice(-maxLen)
        }

        if (digitBuffer.length >= 1) {
            var next = DTF.applyTimeSegment(hours, minutes, roles, activeSegment, digitBuffer)
            hours = next.hours
            minutes = next.minutes
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
        } else if (digitBuffer.length >= 1) {
            var stay = activeSegment
            var buf = digitBuffer
            Qt.callLater(function() {
                selectSegment(stay)
                digitBuffer = buf
            })
        }
    }

    QQC2.TextField {
        id: timeField
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(implicitHeight, TouchUi.controlMinHeight)
        placeholderText: text.length > 0 ? "" : DTF.timePlaceholder()  // Material floats the placeholder above filled fields
        inputMethodHints: Qt.ImhTime | Qt.ImhPreferNumbers
        selectByMouse: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.IBeamCursor
            onPressed: function(mouse) {
                timeField.forceActiveFocus()
                var pos = timeField.positionAt(mouse.x, mouse.y, TextInput.CursorBetweenCharacters)
                timeField.cursorPosition = pos
                root.selectSegmentAtCursor()
                mouse.accepted = true
            }
            onDoubleClicked: function(mouse) {
                root.selectSegmentAtCursor()
                mouse.accepted = true
            }
        }

        Keys.onPressed: function(event) {
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
            if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                event.accepted = true
                root.digitBuffer = ""
                root.selectSegment(root.activeSegment >= 0 ? root.activeSegment : 0)
            }
        }

        onEditingFinished: {
            var parsed = root.parseTime(text)
            if (parsed) {
                root.setTime(parsed.hours, parsed.minutes)
            } else {
                root.refreshText()
            }
            root.activeSegment = -1
            root.digitBuffer = ""
        }
    }

    QQC2.ToolButton {
        Layout.preferredWidth: TouchUi.active ? TouchUi.buttonMinHeight : implicitWidth
        Layout.preferredHeight: TouchUi.active ? TouchUi.buttonMinHeight : implicitHeight
        icon.name: "clock-symbolic"
        text: i18n("Pick time")
        display: QQC2.AbstractButton.IconOnly
        enabled: timeField.enabled
        onClicked: {
            var now = new Date()
            now.setHours(root.hours, root.minutes, 0, 0)
            timePopup.value = now
            timePopup.open()
        }
        QQC2.ToolTip.text: text
        QQC2.ToolTip.visible: hovered && !Kirigami.Settings.isMobile
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    TimePopup {
        id: timePopup
        parent: QQC2.Overlay.overlay
        anchors.centerIn: parent
        onAccepted: root.setTime(value.getHours(), value.getMinutes())
    }

    Component.onCompleted: refreshText()
}
