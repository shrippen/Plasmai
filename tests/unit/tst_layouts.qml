import QtQuick
import QtTest
import "../../contents/code/layouts.js" as Layouts

/** layouts.js: the `layout` key and the wizard answers that pick it. */
TestCase {
    name: "Layouts"

    function test_normalize() {
        compare(Layouts.normalize("tiles"), Layouts.Layout.TILES)
        compare(Layouts.normalize("ring"), Layouts.Layout.RING)
        compare(Layouts.normalize(""), Layouts.Layout.CLASSIC)
        compare(Layouts.normalize(undefined), Layouts.Layout.CLASSIC)
        compare(Layouts.normalize("kanban"), Layouts.Layout.CLASSIC)
    }

    function test_forAnswer() {
        compare(Layouts.forAnswer(Layouts.Answer.SWITCH_OFTEN), Layouts.Layout.TILES)
        compare(Layouts.forAnswer(Layouts.Answer.SEE_DAY), Layouts.Layout.DAYBAND)
        compare(Layouts.forAnswer(Layouts.Answer.WEEKLY), Layouts.Layout.TIMESHEET)
        compare(Layouts.forAnswer(Layouts.Answer.AS_BEFORE), Layouts.Layout.CLASSIC)
        compare(Layouts.forAnswer("nonsense"), Layouts.Layout.CLASSIC)
    }
}
