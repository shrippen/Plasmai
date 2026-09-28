import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../contents/ui/Controls" as Controls

/**
 * contents/ui/Controls, the Plasma side of the controls shared components use
 * (the app's qrc puts Qt Quick Controls there). Needs libplasma (CI: Arch).
 * The attached ToolTip must reach the same object as QQC2.ToolTip.
 */
TestCase {
    name: "Controls"
    when: windowShown

    Rectangle {
        id: target
        width: 40
        height: 40
        Controls.ToolTip.text: "hint"
        Controls.ToolTip.delay: 0
    }

    Controls.Label {
        id: label
        text: "abc"
        elide: Text.ElideRight
    }

    function test_label() {
        compare(label.text, "abc")
        compare(label.elide, Text.ElideRight)
        verify(label.implicitWidth > 0)
    }

    function test_attachedToolTip() {
        compare(target.QQC2.ToolTip.text, "hint")
        compare(target.QQC2.ToolTip.delay, 0)
    }

    // The components the app loads from contents/ui compile in the Plasmoid too
    // (singletons ApiErrors and PlasmaiColors are not creatable; they import no controls).
    function test_sharedComponentsCompile_data() {
        return ["ActiveEditView", "ActivityListRow", "BarChart", "ColorLabelRow", "CreateEntityDialog", "CustomerColorDot", "DateField", "DaySparkline", "StatsView", "FilmDayView", "KanteDayStrip",
                "LoadingRow", "ManualEntryView", "PieChart", "ProjectActivityPickers", "SearchableCombo",
                "StackedBarChart", "TagPicker", "TagPill", "TimeField", "TimesheetMetaFields", "TripMap", "TripSheet",
                "TripSuggestionList", "WeeklyHourChart"].map(function(n) { return { tag: n, name: n } })
    }

    function test_sharedComponentsCompile(data) {
        var c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/" + data.name + ".qml"))
        tryCompare(c, "status", Component.Ready)
    }
}
