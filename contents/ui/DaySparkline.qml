import "arcDraw.js" as Arc
import "../code/dayIntervals.js" as Intervals
import "../code/solar.js" as Solar
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "Kante"

/**
 * Compact 24h sparkline (concept H): night/day bar with work + overtime
 * segments, soft celestial fills, dual sun/moon arcs with on-path icons,
 * a work-hours arc, rise/set ticks, and 3-hour labels.
 */
Item {
    id: root

    /**
     * Masks (rounded track, text cutouts under the sun) are shader effects; Qt's software
     * renderer draws none of them, so there the layers show unmasked instead of vanishing.
     */
    property bool masksRender: root.GraphicsInfo.api !== GraphicsInfo.Software

    property var entries: []
    property int targetSeconds: 0
    property string workDayBegin: Intervals.DEFAULT_WORK_DAY_BEGIN
    property string workDayEnd: Intervals.DEFAULT_WORK_DAY_END
    property real latitude: 52.52
    property real longitude: 13.405
    /** Bump so the live edge and sky refresh (driven at ~30s from main). */
    property int nowTick: 0
    /** When false, keep the bar + labels but hide sun/moon/work arcs. */
    property bool showArcs: true
    /** Parent flyout open — arc icon animators must not run while collapsed. */
    property bool flyoutOpen: true
    /**
     * Header labels that should punch soft holes in the sky arcs (e.g. timer,
     * customer). Mapped into sky-local coordinates on refresh.
     */
    property var headerMaskItems: []
    /**
     * Soft holes punched in the sky arcs under header text.
     * Each entry: { x, y, w, h } in sky Item coordinates.
     */
    property var arcCutouts: []

    function scheduleHeaderCutouts() {
        headerCutoutTimer.restart()
    }

    function refreshHeaderCutouts() {
        if (!root.showArcs || !root.visible || !sky || sky.height < 1) {
            if (arcCutouts.length) {
                arcCutouts = []
            }
            return
        }
        var items = root.headerMaskItems || []
        // Keep prior vertical inset, then shrink both axes another 10%, centered.
        var baseInsetY = 12
        var scaleX = 0.81
        var scaleY = 0.729
        var outs = []
        var i
        for (i = 0; i < items.length; i++) {
            var item = items[i]
            if (!item || item.visible === false || !(item.width > 0) || !(item.height > 0)) {
                continue
            }
            var baseW = item.width
            var baseH = Math.max(1, item.height - baseInsetY * 2)
            var w = Math.max(1, baseW * scaleX)
            var h = Math.max(1, baseH * scaleY)
            var ox = (item.width - w) / 2
            var oy = (item.height - h) / 2
            var p = item.mapToItem(sky, ox, oy)
            outs.push({
                x: p.x,
                y: p.y,
                w: w,
                h: h
            })
        }
        arcCutouts = outs
    }

    Timer {
        id: headerCutoutTimer
        interval: 16
        repeat: false
        onTriggered: root.refreshHeaderCutouts()
    }

    onNowTickChanged: root.scheduleHeaderCutouts()
    onHeaderMaskItemsChanged: root.scheduleHeaderCutouts()
    onShowArcsChanged: root.scheduleHeaderCutouts()
    onWidthChanged: root.scheduleHeaderCutouts()
    onHeightChanged: root.scheduleHeaderCutouts()
    onVisibleChanged: root.scheduleHeaderCutouts()
    Component.onCompleted: root.scheduleHeaderCutouts()

    readonly property var model: {
        var _force = root.nowTick
        return Intervals.buildDaySparklineModel(
            root.entries, root.targetSeconds, root.workDayBegin, root.workDayEnd, Date.now())
    }
    readonly property var sky: {
        var _force = root.nowTick
        return Solar.daySkyModel(
            new Date(), root.latitude, root.longitude,
            root.model.businessStart, root.model.businessEnd)
    }

    readonly property int barHeight: Math.max(17, Math.round(Kirigami.Units.smallSpacing * 2.75 * 1.2))
    readonly property int nowOverhang: Math.max(3, Math.round(Kirigami.Units.smallSpacing))
    readonly property int nowStemWidth: 3
    readonly property int nowKnobSize: Math.max(6, Math.round(Kirigami.Units.smallSpacing * 1.4))
    readonly property int workIconSize: Math.max(18, Math.round(Kirigami.Units.gridUnit * 1.05))
    /**
     * Work-arc peak depth restored to the earlier visual height (~0.48 of the
     * previous 1.55×grid under-band). Band height only wraps the arc + icon
     * with a 2px pad so the gap to the project line stays column spacing.
     */
    readonly property int workUnderPad: 2
    readonly property int skyIconPad: 2
    readonly property int peakWork: Math.max(12, Math.round(Kirigami.Units.gridUnit * 1.55 * 0.48))
    readonly property int workUnderHeightFull: Math.ceil(0.5 + peakWork + workIconSize * 0.5 + workUnderPad)
    // Sky band reserves half the on-path icon above the arc apex (same as work).
    readonly property int skyHeightFull: Math.max(
        38,
        Math.ceil(0.5 + Math.round(Kirigami.Units.gridUnit * 2.35) + workIconSize * 0.5 + skyIconPad))
    readonly property int skyHeight: root.showArcs ? skyHeightFull : 0
    readonly property int workUnderHeight: root.showArcs ? workUnderHeightFull : 0
    readonly property int labelHeight: Math.max(12, Math.round(KanteStyle.smallFont.pixelSize + 2))
    readonly property int peakSun: Math.max(12, skyHeightFull - Math.ceil(0.5 + workIconSize * 0.5 + skyIconPad))
    readonly property int peakMoon: Math.max(12, Math.round(peakSun * 1.12))
    /** Exact Y of the work stroke apex inside the under-bar band. */
    readonly property real workArcApexY: {
        var base = 0.5
        var apex = base + peakWork
        var maxCtrl = workUnderHeightFull - 0.5
        var ctrl = 2 * apex - base
        if (ctrl > maxCtrl) {
            ctrl = maxCtrl
            apex = (base + ctrl) / 2
        }
        return apex
    }
    readonly property real workArcCtrlY: (2 * workArcApexY) - 0.5

    readonly property bool lightBg: KanteStyle.backgroundColor.hslLightness > 0.5
    readonly property color trackOutline: KanteStyle.tint(KanteStyle.textColor, lightBg ? 0.22 : 0.32)
    readonly property color workStroke: KanteStyle.tint(KanteStyle.highlightColor, lightBg ? 0.75 : 0.85)
    readonly property color workRibbon: KanteStyle.tint(KanteStyle.highlightColor, lightBg ? 0.2 : 0.26)

    /** Y center of an on-path icon on a sky arc (matches workArcApexY math). */
    function skyArcIconCenterY(containerHeight, peak, yNorm) {
        return containerHeight - 0.5 - yNorm * peak
    }

    /** Fixed at the work-arc apex (mid business hours). */
    readonly property var workPeak: {
        var w = root.sky.work || {}
        if (!w.valid || !(w.end > w.start)) {
            return { visible: false, xFrac: 0.5 }
        }
        return { visible: true, xFrac: (w.start + w.end) / 2 }
    }

    readonly property real viewStart: {
        var v = root.model.viewStart
        return (typeof v === "number") ? v : 0
    }
    readonly property real viewEnd: {
        var v = root.model.viewEnd
        return (typeof v === "number") ? v : 1
    }
    readonly property real viewSpan: Math.max(1 / 24, root.viewEnd - root.viewStart)

    /** Map a day fraction [0,1] into the zoomed view [0,1] (may fall outside). */
    function mapX(dayFrac) {
        return (dayFrac - root.viewStart) / root.viewSpan
    }

    function inView(dayFrac, pad) {
        var p = (typeof pad === "number") ? pad : 0.02
        var x = root.mapX(dayFrac)
        return x >= -p && x <= 1 + p
    }

    /** Hour tick marks (every hour) inside the current view. */
    readonly property var hourTicks: {
        var v0 = root.viewStart
        var v1 = root.viewEnd
        var startH = Math.ceil(v0 * 24 - 1e-6)
        var endH = Math.floor(v1 * 24 + 1e-6)
        var out = []
        var h
        for (h = startH; h <= endH; h++) {
            if (h > 24) {
                break
            }
            var frac = h / 24
            if (frac < v0 - 1e-9 || frac > v1 + 1e-9) {
                continue
            }
            out.push(frac)
        }
        return out
    }

    /** Hour labels inside the current view (step adapts to zoom width). */
    readonly property var hourMarks: {
        var v0 = root.viewStart
        var v1 = root.viewEnd
        var hours = (v1 - v0) * 24
        var step = hours <= 9 ? 1 : (hours <= 14 ? 2 : 3)
        var startH = Math.ceil(v0 * 24 - 1e-6)
        startH = Math.ceil(startH / step) * step
        var endH = Math.floor(v1 * 24 + 1e-6)
        var out = []
        var h
        for (h = startH; h <= endH; h += step) {
            if (h > 24) {
                break
            }
            var frac = h / 24
            if (frac < v0 - 1e-9 || frac > v1 + 1e-9) {
                continue
            }
            var label = h === 24 ? "24" : ((h < 10 ? "0" : "") + String(h))
            out.push({ hour: h, text: label, frac: frac })
        }
        return out
    }

    implicitWidth: Kirigami.Units.gridUnit * 8
    // Labels sit under the bar; work arc shares that band when visible.
    readonly property int belowBarHeight: Math.max(workUnderHeight, labelHeight + 1)
    implicitHeight: skyHeight + barHeight + nowOverhang + belowBarHeight
    height: implicitHeight
    clip: false
    Accessible.role: Accessible.Chart
    Accessible.name: i18n("Today's tracked time")

    // —— Sky (sun / moon arcs above the bar) ——
    Item {
        id: sky
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.skyHeight
        visible: root.showArcs
        clip: true
        z: 1

        DaySky {
            anchors.fill: parent
            sky: root.sky
            viewStart: root.viewStart
            viewSpan: root.viewSpan
            arcCutouts: root.arcCutouts
            iconSize: root.workIconSize
            peakSun: root.peakSun
            peakMoon: root.peakMoon
            lightBg: root.lightBg
            masksRender: root.masksRender
            flyoutOpen: root.flyoutOpen
        }
    }

    // —— Track ——
    // Layers (bottom → top): moon base → sun → business hours → activities.
    // Item.clip is axis-aligned only, so zoomed fills would square off the
    // capsule ends; a MultiEffect mask keeps every layer rounded at any zoom.
    Item {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: sky.bottom
        height: root.barHeight
        z: 2

        Item {
            id: trackContent
            anchors.fill: parent
            clip: true
            visible: !root.masksRender

            // 0 — Moon base: always full width / full height (not tied to moonrise)
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.22, 0.32, 0.55, root.lightBg ? 0.35 : 0.55)
            }

            // 1 — Sun (full height), soft horizontal bleed into moon base at rise/set
            Canvas {
                id: sunLayerCanvas
                anchors.fill: parent
                antialiasing: true

                readonly property color sunColor: Qt.rgba(1, 0.78, 0.35, root.lightBg ? 0.45 : 0.38)
                /** Fade half-width ≈ 100 minutes of the day (soft bleed into moon base). */
                readonly property real fadeFrac: 100 / 1440

                function repaint() { requestPaint() }

                Connections {
                    target: root
                    function onSkyChanged() { sunLayerCanvas.repaint() }
                    function onModelChanged() { sunLayerCanvas.repaint() }
                    function onLightBgChanged() { sunLayerCanvas.repaint() }
                    function onNowTickChanged() { sunLayerCanvas.repaint() }
                }
                onWidthChanged: repaint()
                onHeightChanged: repaint()
                Component.onCompleted: repaint()

                onPaint: {
                    var ctx = getContext("2d")
                    var w = width
                    var h = height
                    if (w < 2 || h < 2) {
                        return
                    }
                    ctx.clearRect(0, 0, w, h)
                    var sun = root.sky.sun || {}
                    if (!sun.valid || sun.polarNight) {
                        return
                    }

                    var c = sunLayerCanvas.sunColor
                    var rgba = function (a) {
                        return KanteStyle.tint(c, c.a * a)
                    }

                    if (sun.polarDay) {
                        ctx.fillStyle = rgba(1)
                        ctx.fillRect(0, 0, w, h)
                        return
                    }
                    if (!(sun.sunset > sun.sunrise)) {
                        return
                    }

                    // Fade width in view pixels (100 minutes of real day time)
                    var fade = Math.max(8, (sunLayerCanvas.fadeFrac / root.viewSpan) * w)
                    var x0 = root.mapX(sun.sunrise) * w
                    var x1 = root.mapX(sun.sunset) * w
                    var left = x0 - fade
                    var right = x1 + fade
                    if (right <= left) {
                        return
                    }

                    var g = ctx.createLinearGradient(left, 0, right, 0)
                    var span = right - left
                    var stopIn = (x0 - left) / span
                    var stopOut = (x1 - left) / span
                    g.addColorStop(0, rgba(0))
                    g.addColorStop(Math.max(0, Math.min(1, stopIn * 0.35)), rgba(0.12))
                    g.addColorStop(Math.max(0, Math.min(1, stopIn * 0.7)), rgba(0.45))
                    g.addColorStop(Math.max(0, Math.min(1, stopIn)), rgba(1))
                    g.addColorStop(Math.max(0, Math.min(1, stopOut)), rgba(1))
                    g.addColorStop(Math.max(0, Math.min(1, stopOut + (1 - stopOut) * 0.3)), rgba(0.45))
                    g.addColorStop(Math.max(0, Math.min(1, stopOut + (1 - stopOut) * 0.65)), rgba(0.12))
                    g.addColorStop(1, rgba(0))

                    ctx.fillStyle = g
                    ctx.fillRect(left, 0, span, h)
                }
            }

            // 2 — Business hours (¾ height), above sun; flush to lower edge
            Rectangle {
                visible: root.model.businessEnd > root.model.businessStart
                x: Math.round(root.mapX(root.model.businessStart) * track.width)
                width: Math.max(1, Math.round((root.mapX(root.model.businessEnd) - root.mapX(root.model.businessStart)) * track.width))
                height: Math.max(4, Math.round(track.height * 0.75))
                anchors.bottom: parent.bottom
                radius: Math.max(2, height / 2)
                color: Qt.rgba(
                    KanteStyle.highlightColor.r * 0.55 + 0.2,
                    KanteStyle.highlightColor.g * 0.55 + 0.22,
                    KanteStyle.highlightColor.b * 0.55 + 0.35,
                    root.lightBg ? 0.72 : 0.78)
            }

            // Hour ticks (every hour) inside the zoomed view
            Repeater {
                model: root.hourTicks
                delegate: Rectangle {
                    required property real modelData
                    x: Math.round(root.mapX(modelData) * track.width)
                    width: 1
                    height: track.height
                    color: KanteStyle.textColor
                    opacity: 0.2
                }
            }

            // 3 — Activities (½ height), flush to lower edge; normal + overtime
            Repeater {
                model: root.model.segments
                delegate: Rectangle {
                    readonly property real segStart: model.start !== undefined ? model.start : modelData.start
                    readonly property real segEnd: model.end !== undefined ? model.end : modelData.end
                    readonly property bool segOvertime: model.overtime !== undefined ? model.overtime : modelData.overtime

                    x: Math.round(root.mapX(segStart) * track.width)
                    width: Math.max(1, Math.round((root.mapX(segEnd) - root.mapX(segStart)) * track.width))
                    height: Math.max(3, Math.round(track.height * 0.5))
                    anchors.bottom: parent.bottom
                    radius: Math.max(1, height / 4)
                    color: segOvertime ? KanteStyle.neutralTextColor : KanteStyle.positiveTextColor
                    opacity: segOvertime ? 0.92 : 0.9
                }
            }
        }

        Rectangle {
            id: trackMask
            anchors.fill: parent
            radius: height / 2
            color: "#ffffff"
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            visible: root.masksRender
            source: trackContent
            maskEnabled: true
            maskSource: trackMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // Hairline capsule outline (sub-pixel stroke reads thinner than border.width: 1)
    Canvas {
        id: trackOutlineCanvas
        anchors.fill: track
        z: 3
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
        Connections {
            target: root
            function onTrackOutlineChanged() { trackOutlineCanvas.requestPaint() }
            function onBarHeightChanged() { trackOutlineCanvas.requestPaint() }
        }
        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            if (w < 2 || h < 2) {
                return
            }
            ctx.clearRect(0, 0, w, h)
            var r = h / 2
            var o = 0.5
            ctx.beginPath()
            ctx.moveTo(r + o, o)
            ctx.lineTo(w - r - o, o)
            ctx.arc(w - r - o, r, r - o, -Math.PI / 2, Math.PI / 2, false)
            ctx.lineTo(r + o, h - o)
            ctx.arc(r + o, r, r - o, Math.PI / 2, -Math.PI / 2, false)
            ctx.closePath()
            ctx.strokeStyle = root.trackOutline
            ctx.lineWidth = 0.6
            ctx.stroke()
        }
    }

    // —— Work arc hanging below the bar ——
    Item {
        id: workUnder
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: track.bottom
        height: root.workUnderHeight
        visible: root.showArcs
        clip: true
        z: 1

        Canvas {
            id: workCanvas
            anchors.fill: parent
            antialiasing: true

            function repaint() { requestPaint() }

            Connections {
                target: root
                function onNowTickChanged() { workCanvas.repaint() }
                function onSkyChanged() { workCanvas.repaint() }
                function onModelChanged() { workCanvas.repaint() }
                function onWidthChanged() { workCanvas.repaint() }
                function onShowArcsChanged() { workCanvas.repaint() }
            }
            onWidthChanged: repaint()
            onHeightChanged: repaint()
            Component.onCompleted: repaint()

            onPaint: {
                var ctx = getContext("2d")
                var w = width
                var h = height
                if (w < 2 || h < 2) {
                    return
                }
                ctx.clearRect(0, 0, w, h)
                var work = (root.sky.work || {})
                if (!work.valid || !(work.end > work.start)) {
                    return
                }
                var x0 = root.mapX(work.start) * w
                var x1 = root.mapX(work.end) * w
                var mid = (x0 + x1) / 2
                var base = 0.5
                var ctrl = root.workArcCtrlY
                var glowW = Math.max(4, Math.min(9, root.peakWork * 0.45))
                Arc.strokeFadingGlow(ctx, x0, base, mid, ctrl, x1, base, root.workRibbon, glowW)
                Arc.strokeArcLine(ctx, x0, base, mid, ctrl, x1, base, root.workStroke, 1.15, [3, 2])
            }
        }

        Item {
            id: workIcon
            visible: root.workPeak.visible && root.inView(root.workPeak.xFrac, 0.05)
            width: root.workIconSize
            height: root.workIconSize
            x: Math.round(root.mapX(root.workPeak.xFrac) * workUnder.width) - width / 2
            y: Math.round(root.workArcApexY - height / 2)
            z: 4

            Canvas {
                id: workIconCanvas
                anchors.fill: parent
                antialiasing: true
                onPaint: {
                    var ctx = getContext("2d")
                    var s = width
                    var cx = s / 2
                    var cy = s / 2
                    ctx.clearRect(0, 0, s, s)

                    ctx.beginPath()
                    ctx.arc(cx, cy, s * 0.48, 0, Math.PI * 2)
                    ctx.fillStyle = KanteStyle.tint(KanteStyle.backgroundColor, 0.94)
                    ctx.fill()
                    ctx.strokeStyle = root.workStroke
                    ctx.lineWidth = Math.max(1.2, s * 0.06)
                    ctx.stroke()

                    // Briefcase body centered on the disc (and on the arc)
                    var bw = s * 0.62
                    var bh = s * 0.38
                    var bx = cx - bw / 2
                    var by = cy - bh / 2 + s * 0.02
                    var rr = Math.max(1.5, s * 0.06)
                    ctx.fillStyle = root.workStroke
                    ctx.strokeStyle = root.workStroke
                    ctx.lineWidth = Math.max(1.2, s * 0.07)
                    ctx.lineJoin = "round"
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.moveTo(bx + rr, by)
                    ctx.lineTo(bx + bw - rr, by)
                    ctx.quadraticCurveTo(bx + bw, by, bx + bw, by + rr)
                    ctx.lineTo(bx + bw, by + bh - rr)
                    ctx.quadraticCurveTo(bx + bw, by + bh, bx + bw - rr, by + bh)
                    ctx.lineTo(bx + rr, by + bh)
                    ctx.quadraticCurveTo(bx, by + bh, bx, by + bh - rr)
                    ctx.lineTo(bx, by + rr)
                    ctx.quadraticCurveTo(bx, by, bx + rr, by)
                    ctx.closePath()
                    ctx.fill()

                    var hx = bx + bw * 0.28
                    var hw = bw * 0.44
                    var hy = by - s * 0.11
                    ctx.beginPath()
                    ctx.moveTo(hx, by + 1)
                    ctx.lineTo(hx, hy + rr * 0.6)
                    ctx.quadraticCurveTo(hx, hy, hx + rr * 0.6, hy)
                    ctx.lineTo(hx + hw - rr * 0.6, hy)
                    ctx.quadraticCurveTo(hx + hw, hy, hx + hw, hy + rr * 0.6)
                    ctx.lineTo(hx + hw, by + 1)
                    ctx.stroke()

                    ctx.beginPath()
                    ctx.moveTo(bx + 1, by + bh * 0.4)
                    ctx.lineTo(bx + bw - 1, by + bh * 0.4)
                    ctx.strokeStyle = KanteStyle.tint(KanteStyle.backgroundColor, 0.65)
                    ctx.lineWidth = Math.max(1, s * 0.06)
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
                Connections {
                    target: root
                    function onWorkStrokeChanged() { workIconCanvas.requestPaint() }
                    function onLightBgChanged() { workIconCanvas.requestPaint() }
                }
            }
        }
    }

    // Now marker
    Item {
        id: nowMarker
        visible: root.inView(root.model.now, 0.01)
        readonly property real cx: Math.round(root.mapX(root.model.now) * track.width)
        x: cx - Math.ceil(width / 2)
        width: Math.max(root.nowStemWidth + 2, root.nowKnobSize)
        height: track.height + root.nowOverhang * 2 + Math.ceil(root.nowKnobSize / 2)
        anchors.verticalCenter: track.verticalCenter
        anchors.verticalCenterOffset: -Math.ceil(root.nowKnobSize / 4)
        z: 5

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(0, root.nowOverhang - 1)
            width: root.nowStemWidth + 2
            height: track.height + root.nowOverhang * 2
            radius: width / 2
            color: Qt.rgba(0, 0, 0, root.lightBg ? 0.35 : 0.55)
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(0, root.nowOverhang - 1)
            width: root.nowStemWidth
            height: track.height + root.nowOverhang * 2
            radius: width / 2
            color: KanteStyle.textColor
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: root.nowKnobSize
            height: root.nowKnobSize
            radius: width / 2
            color: KanteStyle.textColor
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, root.lightBg ? 0.35 : 0.55)
        }
    }

    // Hour labels — directly under the bar (zoomed view)
    Item {
        id: labelRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: track.bottom
        anchors.topMargin: 1
        height: root.labelHeight
        z: 6

        Repeater {
            model: root.hourMarks
            delegate: Text {
                required property var modelData
                text: modelData.text
                color: KanteStyle.textColor
                opacity: 0.55
                font.pixelSize: Math.max(9, KanteStyle.smallFont.pixelSize - 1)
                y: 0
                x: {
                    var cx = root.mapX(modelData.frac) * labelRow.width
                    var left = cx - width / 2
                    if (left < 0) {
                        return 0
                    }
                    if (left + width > labelRow.width) {
                        return Math.max(0, labelRow.width - width)
                    }
                    return left
                }
            }
        }
    }
}
