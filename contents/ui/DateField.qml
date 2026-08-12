import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/dateTimeFormat.js" as DTF
import "."

/**
 * Locale-formatted date field with click-to-select segments (day/month/year)
 * and a calendar popup.
 */
RowLayout {
    id: root

    property alias enabled: dateField.enabled
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
    property int calendarMonth: (new Date()).getMonth()
    property int calendarYear: (new Date()).getFullYear()

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
        calendarMonth = next.getMonth()
        calendarYear = next.getFullYear()
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

    QQC2.TextField {
        id: dateField
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(implicitHeight, TouchUi.controlMinHeight)
        placeholderText: DTF.datePlaceholder()
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

    PlasmaComponents3.ToolButton {
        icon.name: "view-calendar"
        text: i18n("Pick date")
        display: QQC2.AbstractButton.IconOnly
        enabled: dateField.enabled
        onClicked: {
            var d = DTF.coerceDate(root.selectedDate) || new Date()
            root.calendarMonth = d.getMonth()
            root.calendarYear = d.getFullYear()
            calendarPopup.open()
        }
        PlasmaComponents3.ToolTip.text: text
        PlasmaComponents3.ToolTip.visible: hovered
        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    QQC2.Popup {
        id: calendarPopup
        parent: root
        x: Math.max(0, root.width - width)
        y: dateField.height + Kirigami.Units.smallSpacing
        width: Kirigami.Units.gridUnit * 14
        padding: Kirigami.Units.smallSpacing
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.ToolButton {
                    icon.name: "go-previous"
                    onClicked: {
                        if (root.calendarMonth === 0) {
                            root.calendarMonth = 11
                            root.calendarYear -= 1
                        } else {
                            root.calendarMonth -= 1
                        }
                    }
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.bold: true
                    text: Qt.locale().standaloneMonthName(root.calendarMonth) + " " + root.calendarYear
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "go-next"
                    onClicked: {
                        if (root.calendarMonth === 11) {
                            root.calendarMonth = 0
                            root.calendarYear += 1
                        } else {
                            root.calendarMonth += 1
                        }
                    }
                }
            }

            DayOfWeekRow {
                Layout.fillWidth: true
                locale: Qt.locale()
            }

            MonthGrid {
                id: monthGrid
                Layout.fillWidth: true
                month: root.calendarMonth
                year: root.calendarYear
                locale: Qt.locale()
                spacing: 2

                delegate: QQC2.ItemDelegate {
                    required property var model
                    implicitWidth: Kirigami.Units.gridUnit * TouchUi.calendarCellGu
                    implicitHeight: Kirigami.Units.gridUnit * TouchUi.calendarCellGu
                    enabled: model.month === monthGrid.month
                    highlighted: {
                        var sel = DTF.coerceDate(root.selectedDate)
                        return !!sel
                                 && model.year === sel.getFullYear()
                                 && model.month === sel.getMonth()
                                 && model.day === sel.getDate()
                    }
                    contentItem: PlasmaComponents3.Label {
                        text: model.day
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: model.month === monthGrid.month ? 1 : 0.35
                        font.bold: parent.highlighted
                    }
                    onClicked: {
                        root.setDate(new Date(model.year, model.month, model.day, 12, 0, 0, 0))
                        calendarPopup.close()
                    }
                }
            }
        }
    }

    Component.onCompleted: refreshText()
}
