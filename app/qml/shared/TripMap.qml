import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../../contents/code/geocode.js" as Geocode
import "../../contents/code/tripMap.js" as TripMap
import "../Kante"

/**
 * Map of a trip's start and destination (OpenStreetMap), to check that both
 * places are the intended ones. The places are looked up online after a
 * short pause in typing; the entered km are compared with the straight line.
 */
ColumnLayout {
    id: root

    property string from: ""
    property string to: ""
    /** One way, as entered (NaN when empty). */
    property real enteredKm: NaN

    property var fromPlace: null
    property var toPlace: null
    property bool searching: false
    property int serial: 0

    readonly property bool hasQuery: from.trim().length > 0 || to.trim().length > 0
    readonly property var points: [fromPlace, toPlace].filter(function(p) { return !!p })
    readonly property real straightKm: fromPlace && toPlace ? TripMap.distanceKm(fromPlace, toPlace) : NaN
    readonly property string distanceCheck: TripMap.checkDistance(straightKm, enteredKm)

    visible: hasQuery
    spacing: Kirigami.Units.smallSpacing

    onFromChanged: lookupTimer.restart()
    onToChanged: lookupTimer.restart()

    // One place after the other: Nominatim allows one request per second.
    /** Coordinates need no search. */
    function place(query, callback) {
        var p = TripMap.parseCoordinates(query)
        if (p) {
            callback(p)
            return
        }
        Geocode.lookup(query, callback)
    }

    function lookup() {
        var s = ++serial
        searching = true
        root.place(from, function(a) {
            if (s !== root.serial) {
                return
            }
            root.fromPlace = a
            root.place(root.to, function(b) {
                if (s !== root.serial) {
                    return
                }
                root.toPlace = b
                root.searching = false
            })
        })
    }

    /** Straight line: whole km from 10 on; entered km (exact) keep their decimal. */
    function kmText(km, exact) {
        var decimals = exact ? (km % 1 === 0 ? 0 : 1) : (km < 10 ? 1 : 0)
        return Number(km).toLocaleString(Qt.locale(), "f", decimals)
    }

    Timer {
        id: lookupTimer
        interval: 900
        onTriggered: root.lookup()
    }

    Rectangle {
        id: mapBox
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 10
        clip: true
        color: KanteStyle.backgroundColor
        border.width: 1
        border.color: KanteStyle.frameColor
        visible: root.points.length > 0

        readonly property var view: root.points.length > 0 && width > 0
            ? TripMap.fitView(root.points, width, height, Kirigami.Units.gridUnit * 1.5, 15) : null
        readonly property var fromPos: view && root.fromPlace ? TripMap.toView(root.fromPlace, view) : null
        readonly property var toPos: view && root.toPlace ? TripMap.toView(root.toPlace, view) : null

        Repeater {
            model: mapBox.view ? TripMap.tiles(mapBox.view) : []
            Image {
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: TripMap.TILE
                height: TripMap.TILE
                source: modelData.url
                asynchronous: true
                cache: true
            }
        }

        Canvas {
            id: routeLine
            anchors.fill: parent
            visible: !!mapBox.fromPos && !!mapBox.toPos
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                if (!mapBox.fromPos || !mapBox.toPos) {
                    return
                }
                ctx.strokeStyle = KanteStyle.accentColor
                ctx.lineWidth = 3
                ctx.setLineDash([6, 4])
                ctx.beginPath()
                ctx.moveTo(mapBox.fromPos.x, mapBox.fromPos.y)
                ctx.lineTo(mapBox.toPos.x, mapBox.toPos.y)
                ctx.stroke()
            }
            Connections {
                target: mapBox
                function onFromPosChanged() { routeLine.requestPaint() }
                function onToPosChanged() { routeLine.requestPaint() }
            }
        }

        Repeater {
            model: [{ pos: mapBox.fromPos, label: "A" }, { pos: mapBox.toPos, label: "B" }]
            Rectangle {
                required property var modelData
                visible: !!modelData.pos
                width: Kirigami.Units.gridUnit * 1.4
                height: width
                radius: width / 2
                x: modelData.pos ? modelData.pos.x - width / 2 : 0
                y: modelData.pos ? modelData.pos.y - height / 2 : 0
                color: KanteStyle.accentColor
                border.width: 2
                border.color: "white"
                QQC2.Label {
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    font.bold: true
                    color: "black"
                }
            }
        }

        // OpenStreetMap asks for this attribution on every map.
        QQC2.Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            padding: 2
            text: i18n("© OpenStreetMap contributors")
            font.pointSize: KanteStyle.smallFont.pointSize * 0.85
            color: "black"
            background: Rectangle { color: Qt.rgba(1, 1, 1, 0.75) }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !!root.fromPlace && !!root.toPlace
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: Qt.openUrlExternally(TripMap.routeUrl(root.fromPlace, root.toPlace))
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: root.searching && root.points.length === 0
        text: i18n("Looking up the places…")
        color: KanteStyle.mutedTextColor
        font.pointSize: KanteStyle.smallFont.pointSize
    }

    Repeater {
        model: [{ query: root.from, place: root.fromPlace, label: "A" }, { query: root.to, place: root.toPlace, label: "B" }]
        QQC2.Label {
            required property var modelData
            Layout.fillWidth: true
            visible: modelData.query.trim().length > 0 && !root.searching
            text: modelData.label + ": " + (modelData.place ? modelData.place.displayName
                                                           : i18n("\"%1\" was not found", modelData.query.trim()))
            color: modelData.place ? KanteStyle.mutedTextColor : KanteStyle.negativeTextColor
            font.pointSize: KanteStyle.smallFont.pointSize
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: !isNaN(root.straightKm) && !root.searching
        wrapMode: Text.WordWrap
        font.pointSize: KanteStyle.smallFont.pointSize
        color: root.distanceCheck === "shorter" || root.distanceCheck === "longer" ? KanteStyle.neutralTextColor : KanteStyle.mutedTextColor
        text: {
            var line = isNaN(root.enteredKm) || root.enteredKm <= 0
                ? i18n("Straight line %1 km", root.kmText(root.straightKm))
                : i18n("Straight line %1 km · entered %2 km one way", root.kmText(root.straightKm), root.kmText(root.enteredKm, true))
            if (root.distanceCheck === "shorter") {
                line += " — " + i18n("shorter than the straight line: check the places or the km.")
            } else if (root.distanceCheck === "longer") {
                line += " — " + i18n("far longer than the straight line: check the places.")
            }
            return line
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: !!root.fromPlace && !!root.toPlace
        text: i18n("Tap the map to open the route.")
        color: KanteStyle.mutedTextColor
        font.pointSize: KanteStyle.smallFont.pointSize
    }
}
