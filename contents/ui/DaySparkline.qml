import QtQuick
import org.kde.kirigami as Kirigami
import "../code/kimaiApi.js" as KimaiApi
import "../code/solar.js" as Solar

/**
 * Tiny 24h day bar: daylight band (sunrise–sunset), hour ticks, usual work
 * window, tracked intervals, and overtime.
 */
Item {
    id: root

    property var entries: []
    property int targetSeconds: 0
    property string workDayBegin: KimaiApi.DEFAULT_WORK_DAY_BEGIN
    property string workDayEnd: KimaiApi.DEFAULT_WORK_DAY_END
    property real latitude: 52.52
    property real longitude: 13.405
    /** Bump (e.g. elapsedSeconds) so the live edge and “now” marker refresh. */
    property int nowTick: 0

    readonly property var model: {
        var _force = root.nowTick
        return KimaiApi.buildDaySparklineModel(
            root.entries,
            root.targetSeconds,
            root.workDayBegin,
            root.workDayEnd,
            Date.now()
        )
    }

    readonly property var solar: {
        var _force = root.nowTick
        return Solar.daySolarFractions(new Date(), root.latitude, root.longitude)
    }

    readonly property int barHeight: Math.max(8, Math.round(Kirigami.Units.smallSpacing * 1.5))
    /** Extra pixels the “now” needle sticks out above/below the bar. */
    readonly property int nowOverhang: Math.max(2, Math.round(Kirigami.Units.smallSpacing * 0.6))

    implicitHeight: barHeight + nowOverhang * 2
    implicitWidth: Kirigami.Units.gridUnit * 8
    height: implicitHeight
    clip: false

    Accessible.role: Accessible.Chart
    Accessible.name: i18n("Today's tracked time across 24 hours")

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.barHeight
        radius: height / 2
        // Night sky base
        color: Qt.rgba(0.15, 0.22, 0.40,
                       Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? 0.22 : 0.45)

        // Daylight band (sunrise → sunset)
        Rectangle {
            visible: root.solar.valid && root.solar.sunset > root.solar.sunrise
            x: Math.round(root.solar.sunrise * track.width)
            width: Math.max(1, Math.round((root.solar.sunset - root.solar.sunrise) * track.width))
            height: track.height
            radius: track.radius
            color: Qt.rgba(1.0, 0.78, 0.35,
                           Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? 0.28 : 0.22)
        }

        // Usual work window (calendar.businessHours)
        Rectangle {
            visible: root.model.businessEnd > root.model.businessStart
            x: Math.round(root.model.businessStart * track.width)
            width: Math.max(1, Math.round((root.model.businessEnd - root.model.businessStart) * track.width))
            height: track.height
            radius: track.radius
            color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                           Kirigami.Theme.highlightColor.g,
                           Kirigami.Theme.highlightColor.b, 0.30)
        }

        // Hour tick marks (1:00 … 23:00)
        Repeater {
            model: 23
            delegate: Rectangle {
                required property int index
                readonly property int hour: index + 1
                x: Math.round(hour / 24 * track.width)
                width: 1
                height: track.height
                color: Kirigami.Theme.textColor
                opacity: hour % 6 === 0 ? 0.40 : 0.18
            }
        }

        Repeater {
            model: root.model.segments

            delegate: Rectangle {
                readonly property real segStart: model.start !== undefined ? model.start : modelData.start
                readonly property real segEnd: model.end !== undefined ? model.end : modelData.end
                readonly property bool segOvertime: model.overtime !== undefined ? model.overtime : modelData.overtime

                x: Math.round(segStart * track.width)
                width: Math.max(1, Math.round((segEnd - segStart) * track.width))
                height: Math.max(2, track.height - 2)
                anchors.verticalCenter: track.verticalCenter
                radius: 1
                color: segOvertime
                       ? Kirigami.Theme.neutralTextColor
                       : Kirigami.Theme.positiveTextColor
                opacity: segOvertime ? 0.9 : 0.85
            }
        }
    }

    // Current time marker — taller than the bar so it peeks out top and bottom
    Rectangle {
        x: Math.round(root.model.now * track.width) - 1
        width: 2
        height: track.height + root.nowOverhang * 2
        anchors.verticalCenter: track.verticalCenter
        radius: 1
        z: 2
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.85)
    }
}
