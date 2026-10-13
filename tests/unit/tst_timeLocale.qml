import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../contents/ui"
import "../../contents/ui/Kante"
import "../../contents/code/dateTimeFormat.js" as DTF

/**
 * Times in the current locale: what a time field shows reads back as the same
 * time, in 24- and 12-hour locales, with Latin or native digits.
 * tests/locales.sh runs this file under many locales.
 */
TestCase {
    name: "TimeLocale"
    when: windowShown
    width: 400
    height: 400

    readonly property var samples: [[0, 0], [0, 45], [9, 30], [11, 59], [12, 0], [12, 15], [13, 5], [18, 30], [23, 59]]

    function label(h, m) {
        return Qt.locale().name + " " + h + ":" + m
    }

    // dateTimeFormat.js: format, then read back.
    function test_formatParseRoundTrip() {
        for (const s of samples) {
            const text = DTF.formatLocaleTime(s[0], s[1])
            const back = DTF.parseLocaleTime(text)
            verify(back !== null, label(s[0], s[1]) + " '" + text + "' unreadable")
            compare([back.hours, back.minutes], s, label(s[0], s[1]) + " '" + text + "'")
        }
    }

    // The System time field: set, shown, read back.
    function test_timeFieldRoundTrip() {
        KanteStyle.kind = KanteStyle.Kind.System
        const field = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/TimeField.qml")), this, { width: 300 })
        for (const s of samples) {
            field.setTime(s[0], s[1])
            const back = field.parseTime(field.text)
            verify(back !== null, label(s[0], s[1]) + " '" + field.text + "' unreadable")
            compare([back.hours, back.minutes], s, label(s[0], s[1]) + " '" + field.text + "'")
        }
    }

    // The Kante time field: text of a time reads back as that time.
    function test_kanteTimeFieldRoundTrip() {
        const field = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../contents/ui/Kante/KanteTimeField.qml")), this, { width: 300 })
        for (const s of samples) {
            const text = field.textOf(s[0], s[1])
            const back = field.parse(text)
            verify(back !== null && back !== undefined, label(s[0], s[1]) + " '" + text + "' unreadable")
            compare([back.hour, back.minute], s, label(s[0], s[1]) + " '" + text + "'")
        }
    }
}
