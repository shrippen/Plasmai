import QtQuick
import QtTest
import "../../contents/ui" as Shared

// Setting a time from code is not an edit: the film day saves begin and end
// directly on timeEdited, so a load must not report one (it wrote to Kimai).
TestCase {
    name: "TimeField"
    when: windowShown

    Component {
        id: fieldComponent
        Shared.TimeField { }
    }

    SignalSpy {
        id: spy
        signalName: "timeEdited"
    }

    function test_setTimeIsNoEdit() {
        var f = createTemporaryObject(fieldComponent, this)
        spy.clear()
        spy.target = f
        f.setTime(7, 35)
        compare(f.hours, 7)
        compare(f.minutes, 35)
        compare(spy.count, 0)
    }
}
