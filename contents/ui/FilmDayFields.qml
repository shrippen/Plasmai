import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/drehzettelApi.js" as DrehzettelApi
import "."

/**
 * Drehzettel film-day fields for the timesheet entry form - "Konzept A,
 * Inline Expand" from kimai-drehzettel-bundle/research/ux-flows-film-day-data.md:
 * a "Drehtag" toggle that unfolds break/catering/category/note directly
 * beneath it, pre-filled from the active engagement and manually
 * overridable (e.g. a sick day inside an otherwise active engagement).
 *
 * Only shown when the project+date fall inside an active engagement -
 * the plugin API itself only accepts film-day writes in that case, there
 * is no "declare a day a film day without an engagement" capability.
 */
ColumnLayout {
    id: root

    /** Whether project+date currently fall inside an active engagement. */
    property bool engagementActive: false
    property string rulesetName: ""

    readonly property bool filmDay: toggle.checked
    readonly property var breakMinutes: breakField.text.trim().length > 0 ? parseInt(breakField.text, 10) : null
    readonly property bool catering: cateringCheck.checked
    readonly property string category: categoryCombo.currentIndex > 0
                                        ? DrehzettelApi.CATEGORIES[categoryCombo.currentIndex - 1] : ""
    readonly property string note: noteField.text

    visible: root.engagementActive
    spacing: Kirigami.Units.smallSpacing

    readonly property var categoryLabels: [
        i18n("Automatic"),
        i18n("Weekday"),
        i18n("Saturday"),
        i18n("Sunday"),
        i18n("Holiday")
    ]

    function categoryIndex(value) {
        if (!value) {
            return 0
        }
        var idx = DrehzettelApi.CATEGORIES.indexOf(value)
        return idx >= 0 ? idx + 1 : 0
    }

    /** filmDay: { breakMinutes, catering, category, note } or null (nothing saved yet). */
    function loadFilmDay(filmDayData, active, ruleset) {
        engagementActive = !!active
        rulesetName = ruleset || ""
        toggle.checked = !!active
        var d = filmDayData || {}
        breakField.text = (d.breakMinutes === null || d.breakMinutes === undefined) ? "" : String(d.breakMinutes)
        cateringCheck.checked = !!d.catering
        categoryCombo.currentIndex = categoryIndex(d.category)
        noteField.text = d.note || ""
    }

    function resetDefaults() {
        engagementActive = false
        rulesetName = ""
        toggle.checked = false
        breakField.text = ""
        cateringCheck.checked = false
        categoryCombo.currentIndex = 0
        noteField.text = ""
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
    }

    QQC2.CheckBox {
        id: toggle
        Layout.fillWidth: true
        enabled: root.enabled
        checked: true
        text: root.rulesetName.length > 0
              ? i18n("Film day (%1)", root.rulesetName)
              : i18n("Film day")
        Accessible.name: text
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.smallSpacing
        visible: toggle.checked

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: i18n("Break (min)")
                opacity: 0.85
            }
            QQC2.TextField {
                id: breakField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                enabled: root.enabled
                placeholderText: i18n("Default")
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 1440 }
                Accessible.name: i18n("Break (min)")
            }

            Item { Layout.fillWidth: true }

            QQC2.CheckBox {
                id: cateringCheck
                enabled: root.enabled
                text: i18n("Catering")
                Accessible.name: text
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: i18n("Category")
                opacity: 0.85
            }
            QQC2.ComboBox {
                id: categoryCombo
                Layout.fillWidth: true
                enabled: root.enabled
                model: root.categoryLabels
                Accessible.name: i18n("Category")
            }
        }

        QQC2.TextField {
            id: noteField
            Layout.fillWidth: true
            enabled: root.enabled
            placeholderText: i18n("Note (optional)")
            Accessible.name: i18n("Note")
        }
    }
}
