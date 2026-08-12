import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/dateTimeFormat.js" as DTF
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
        placeholderText: DTF.timePlaceholder()
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

    PlasmaComponents3.ToolButton {
        icon.name: "clock-symbolic"
        text: i18n("Pick time")
        display: QQC2.AbstractButton.IconOnly
        enabled: timeField.enabled
        onClicked: {
            hourTumbler.currentIndex = root.hours
            minuteTumbler.currentIndex = root.minutes
            timePopup.open()
        }
        PlasmaComponents3.ToolTip.text: text
        PlasmaComponents3.ToolTip.visible: hovered
        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    QQC2.Popup {
        id: timePopup
        parent: root
        x: Math.max(0, root.width - width)
        y: timeField.height + Kirigami.Units.smallSpacing
        width: Kirigami.Units.gridUnit * (TouchUi.active ? 12 : 10)
        padding: Kirigami.Units.smallSpacing
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.75
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: i18n("Hours : Minutes")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing

                QQC2.Tumbler {
                    id: hourTumbler
                    Layout.preferredWidth: Kirigami.Units.gridUnit * TouchUi.tumblerWidthGu
                    Layout.preferredHeight: Kirigami.Units.gridUnit * TouchUi.tumblerHeightGu
                    model: 24
                    visibleItemCount: 5
                    delegate: PlasmaComponents3.Label {
                        text: DTF.pad2(modelData)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: Math.abs(QQC2.Tumbler.displacement) < 0.5 ? 1 : 0.4
                        font.bold: Math.abs(QQC2.Tumbler.displacement) < 0.5
                    }
                }

                PlasmaComponents3.Label {
                    text: ":"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                }

                QQC2.Tumbler {
                    id: minuteTumbler
                    Layout.preferredWidth: Kirigami.Units.gridUnit * TouchUi.tumblerWidthGu
                    Layout.preferredHeight: Kirigami.Units.gridUnit * TouchUi.tumblerHeightGu
                    model: 60
                    visibleItemCount: 5
                    delegate: PlasmaComponents3.Label {
                        text: DTF.pad2(modelData)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: Math.abs(QQC2.Tumbler.displacement) < 0.5 ? 1 : 0.4
                        font.bold: Math.abs(QQC2.Tumbler.displacement) < 0.5
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Button {
                    Layout.fillWidth: true
                    text: i18n("Cancel")
                    onClicked: timePopup.close()
                }
                PlasmaComponents3.Button {
                    Layout.fillWidth: true
                    text: i18n("Select")
                    icon.name: "dialog-ok-apply"
                    onClicked: {
                        root.setTime(hourTumbler.currentIndex, minuteTumbler.currentIndex)
                        timePopup.close()
                    }
                }
            }
        }
    }

    Component.onCompleted: refreshText()
}
