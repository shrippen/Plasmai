import "../code/kimaiApi.js" as KimaiApi
import "../code/solar.js" as Solar
import Qt5Compat.GraphicalEffects as GE
import QtQuick
import org.kde.kirigami as Kirigami

/**
 * Compact 24h sparkline (concept H): night/day bar with work + overtime
 * segments, soft celestial fills, dual sun/moon arcs with on-path icons,
 * a work-hours arc, rise/set ticks, and 3-hour labels.
 */
Item {
    id: root

    property var entries: []
    property int targetSeconds: 0
    property string workDayBegin: KimaiApi.DEFAULT_WORK_DAY_BEGIN
    property string workDayEnd: KimaiApi.DEFAULT_WORK_DAY_END
    property real latitude: 52.52
    property real longitude: 13.405
    /** Bump (e.g. elapsedSeconds) so the live edge and sky refresh. */
    property int nowTick: 0
    /** When false, keep the bar + labels but hide sun/moon/work arcs. */
    property bool showArcs: true
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
        skyCanvas.requestPaint()
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
        return KimaiApi.buildDaySparklineModel(
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
    readonly property int skyHeightFull: Math.max(38, Math.round(Kirigami.Units.gridUnit * 2.35))
    readonly property int workIconSize: Math.max(18, Math.round(Kirigami.Units.gridUnit * 1.05))
    /**
     * Work-arc peak depth restored to the earlier visual height (~0.48 of the
     * previous 1.55×grid under-band). Band height only wraps the arc + icon
     * with a 2px pad so the gap to the project line stays column spacing.
     */
    readonly property int workUnderPad: 2
    readonly property int peakWork: Math.max(12, Math.round(Kirigami.Units.gridUnit * 1.55 * 0.48))
    readonly property int workUnderHeightFull: Math.ceil(0.5 + peakWork + workIconSize * 0.5 + workUnderPad)
    readonly property int skyHeight: root.showArcs ? skyHeightFull : 0
    readonly property int workUnderHeight: root.showArcs ? workUnderHeightFull : 0
    readonly property int labelHeight: Math.max(12, Math.round(Kirigami.Theme.smallFont.pixelSize + 2))
    readonly property int iconSize: Math.max(9, Math.round(Kirigami.Units.smallSpacing * 2))
    readonly property int peakSun: Math.round(skyHeightFull * 0.88)
    readonly property int peakMoon: Math.round(skyHeightFull * 0.98)
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

    readonly property bool lightBg: Kirigami.Theme.backgroundColor.hslLightness > 0.5
    readonly property color trackOutline: Qt.rgba(
        Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
        Kirigami.Theme.textColor.b, lightBg ? 0.22 : 0.32)
    readonly property color sunStroke: Qt.rgba(1, 0.78, 0.28, lightBg ? 0.85 : 0.9)
    // Soft ribbons along arcs (not solid humps) so overlaps stay readable
    readonly property color sunRibbon: Qt.rgba(1, 0.78, 0.35, lightBg ? 0.28 : 0.35)
    readonly property color moonStroke: Qt.rgba(0.75, 0.82, 1, lightBg ? 0.75 : 0.85)
    readonly property color moonRibbon: Qt.rgba(0.6, 0.7, 1, lightBg ? 0.22 : 0.28)
    readonly property color workStroke: Qt.rgba(
        Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
        Kirigami.Theme.highlightColor.b, lightBg ? 0.75 : 0.85)
    readonly property color workRibbon: Qt.rgba(
        Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
        Kirigami.Theme.highlightColor.b, lightBg ? 0.2 : 0.26)

    /** Point on quadratic Bézier at t ∈ [0,1]. */
    function quadPoint(x0, y0, cx, cy, x1, y1, t) {
        var u = 1 - t
        return {
            x: u * u * x0 + 2 * u * t * cx + t * t * x1,
            y: u * u * y0 + 2 * u * t * cy + t * t * y1
        }
    }

    /**
     * Soft glow along a quadratic arc that fades (and thins) toward the ends.
     * baseY/ctrlY/endY: absolute canvas coordinates.
     */
    function strokeFadingGlow(ctx, x0, y0, cx, cy, x1, y1, color, maxWidth) {
        // Round-capped segments read as dots unless they overlap heavily.
        // Density tracks arc length (≈ span) and stroke width, with no low cap.
        var span = Math.abs(x1 - x0)
        var rise = Math.abs(cy - (y0 + y1) * 0.5)
        var approxLen = Math.sqrt(span * span + rise * rise * 4) * 1.05
        var spacing = Math.max(1.2, Math.min(2.2, maxWidth * 0.22))
        var steps = Math.max(48, Math.min(2400, Math.ceil(approxLen / spacing)))
        var prev = root.quadPoint(x0, y0, cx, cy, x1, y1, 0)
        var i
        for (i = 1; i <= steps; i++) {
            var t = i / steps
            var p = root.quadPoint(x0, y0, cx, cy, x1, y1, t)
            // Smooth fade: 0 at feet, 1 at apex
            var env = Math.sin(Math.PI * t)
            env = env * env
            if (env < 0.02) {
                prev = p
                continue
            }
            ctx.beginPath()
            ctx.moveTo(prev.x, prev.y)
            ctx.lineTo(p.x, p.y)
            ctx.strokeStyle = Qt.rgba(color.r, color.g, color.b, color.a * env)
            ctx.lineWidth = maxWidth * (0.35 + 0.65 * env)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.setLineDash([])
            ctx.stroke()
            prev = p
        }
    }

    function strokeArcLine(ctx, x0, y0, cx, cy, x1, y1, color, width, dash) {
        ctx.beginPath()
        ctx.moveTo(x0, y0)
        ctx.quadraticCurveTo(cx, cy, x1, y1)
        ctx.strokeStyle = color
        ctx.lineWidth = width
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        if (dash && dash.length) {
            ctx.setLineDash(dash)
        } else {
            ctx.setLineDash([])
        }
        ctx.stroke()
        ctx.setLineDash([])
    }

    /** Soft destination-out holes so arcs vanish under header text. */
    function punchArcCutouts(ctx, cutouts) {
        if (!cutouts || !cutouts.length) {
            return
        }
        // Extra-wide soft falloff; vertical closeness comes from cutout height inset.
        var feather = Math.max(36, Math.round(Kirigami.Units.gridUnit * 2.1))
        var steps = Math.max(26, Math.round(feather * 1.1))
        ctx.save()
        ctx.globalCompositeOperation = "destination-out"
        var i
        var s
        for (i = 0; i < cutouts.length; i++) {
            var c = cutouts[i]
            if (!c || !(c.w > 0) || !(c.h > 0)) {
                continue
            }
            for (s = 0; s < steps; s++) {
                var t = s / Math.max(1, steps - 1)
                var expand = feather * (1 - t)
                // Soft falloff — erase weak until close to the cutout core
                var alpha = Math.pow(t, 2.6)
                if (alpha < 0.015) {
                    continue
                }
                ctx.beginPath()
                var x = c.x - expand
                var y = c.y - expand
                var rw = c.w + expand * 2
                var rh = c.h + expand * 2
                var r = Math.min(rh * 0.5, 10 + expand * 0.55)
                ctx.moveTo(x + r, y)
                ctx.lineTo(x + rw - r, y)
                ctx.quadraticCurveTo(x + rw, y, x + rw, y + r)
                ctx.lineTo(x + rw, y + rh - r)
                ctx.quadraticCurveTo(x + rw, y + rh, x + rw - r, y + rh)
                ctx.lineTo(x + r, y + rh)
                ctx.quadraticCurveTo(x, y + rh, x, y + rh - r)
                ctx.lineTo(x, y + r)
                ctx.quadraticCurveTo(x, y, x + r, y)
                ctx.closePath()
                ctx.fillStyle = Qt.rgba(0, 0, 0, Math.min(1, alpha))
                ctx.fill()
            }
            // Solid core = inset cutout bounds
            ctx.beginPath()
            var cx = c.x
            var cy = c.y
            var cw = c.w
            var ch = c.h
            var cr = Math.min(ch * 0.4, 4)
            ctx.moveTo(cx + cr, cy)
            ctx.lineTo(cx + cw - cr, cy)
            ctx.quadraticCurveTo(cx + cw, cy, cx + cw, cy + cr)
            ctx.lineTo(cx + cw, cy + ch - cr)
            ctx.quadraticCurveTo(cx + cw, cy + ch, cx + cw - cr, cy + ch)
            ctx.lineTo(cx + cr, cy + ch)
            ctx.quadraticCurveTo(cx, cy + ch, cx, cy + ch - cr)
            ctx.lineTo(cx, cy + cr)
            ctx.quadraticCurveTo(cx, cy, cx + cr, cy)
            ctx.closePath()
            ctx.fillStyle = Qt.rgba(0, 0, 0, 1)
            ctx.fill()
        }
        ctx.restore()
    }

    function pointInCutouts(px, py) {
        var cutouts = root.arcCutouts
        if (!cutouts || !cutouts.length) {
            return false
        }
        var i
        for (i = 0; i < cutouts.length; i++) {
            var c = cutouts[i]
            if (!c) {
                continue
            }
            var pad = Math.max(4, Math.round(Kirigami.Units.smallSpacing * 0.5))
            if (px >= c.x - pad && px <= c.x + c.w + pad
                && py >= c.y - pad && py <= c.y + c.h + pad) {
                return true
            }
        }
        return false
    }

    readonly property var sunPoint: {
        var _force = root.nowTick
        var s = root.sky.sun || {}
        if (s.polarDay) {
            return Solar.arcPoint(0, 1, root.sky.now, false)
        }
        if (s.polarNight || !s.valid) {
            return { visible: false, xFrac: 0, yNorm: 0, t: 0 }
        }
        return Solar.arcPoint(s.sunrise, s.sunset, root.sky.now, false)
    }
    readonly property var moonPoint: {
        var _force = root.nowTick
        var m = root.sky.moon || {}
        if (!m.valid || m.alwaysDown) {
            return { visible: false, xFrac: 0, yNorm: 0, t: 0 }
        }
        if (m.alwaysUp) {
            return Solar.arcPoint(0, 1, root.sky.now, false)
        }
        return Solar.arcPoint(m.moonrise, m.moonset, root.sky.now, !!m.wraps)
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

        Canvas {
            id: skyCanvas
            anchors.fill: parent
            antialiasing: true

            function repaint() { requestPaint() }

            Connections {
                target: root
                function onNowTickChanged() { skyCanvas.repaint() }
                function onSkyChanged() { skyCanvas.repaint() }
                function onModelChanged() { skyCanvas.repaint() }
                function onWidthChanged() { skyCanvas.repaint() }
                function onShowArcsChanged() { skyCanvas.repaint() }
                function onArcCutoutsChanged() { skyCanvas.repaint() }
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
                var skyModel = root.sky
                var sun = skyModel.sun || {}
                var moon = skyModel.moon || {}

                function drawSpan(rise, set, wraps, peak, ribbon, stroke, dash) {
                    if (wraps) {
                        drawCurve(rise, 1, peak, ribbon, stroke, dash)
                        drawCurve(0, set, peak, ribbon, stroke, dash)
                    } else if (set > rise) {
                        drawCurve(rise, set, peak, ribbon, stroke, dash)
                    }
                }

                function drawCurve(rise, set, peak, ribbon, stroke, dash) {
                    if (!(set > rise)) {
                        return
                    }
                    var x0 = root.mapX(rise) * w
                    var x1 = root.mapX(set) * w
                    var mid = (x0 + x1) / 2
                    var base = h - 0.5
                    var top = base - peak
                    var glowW = Math.max(4, Math.min(9, peak * 0.28))
                    root.strokeFadingGlow(ctx, x0, base, mid, top, x1, base, ribbon, glowW)
                    root.strokeArcLine(ctx, x0, base, mid, top, x1, base, stroke, 1.15, dash)
                }

                if (sun.valid && !sun.polarNight) {
                    if (sun.polarDay) {
                        drawSpan(0, 1, false, root.peakSun, root.sunRibbon, root.sunStroke, [])
                    } else {
                        drawSpan(sun.sunrise, sun.sunset, false, root.peakSun,
                                 root.sunRibbon, root.sunStroke, [])
                    }
                }
                if (moon.valid && !moon.alwaysDown) {
                    if (moon.alwaysUp) {
                        drawSpan(0, 1, false, root.peakMoon, root.moonRibbon, root.moonStroke, [2, 2])
                    } else {
                        drawSpan(moon.moonrise, moon.moonset, !!moon.wraps, root.peakMoon,
                                 root.moonRibbon, root.moonStroke, [2, 2])
                    }
                }

                // Feathered holes under timer / customer — no dark scrim, just no arcs
                root.punchArcCutouts(ctx, root.arcCutouts)
            }
        }

        // Rise / set downward chevrons at arc feet
        Repeater {
            model: {
                var out = []
                var s = root.sky.sun || {}
                var m = root.sky.moon || {}
                if (s.valid && !s.polarNight && !s.polarDay) {
                    out.push({ frac: s.sunrise, kind: "sun" })
                    out.push({ frac: s.sunset, kind: "sun" })
                }
                if (m.valid && !m.alwaysUp && !m.alwaysDown) {
                    out.push({ frac: m.moonrise, kind: "moon" })
                    out.push({ frac: m.moonset, kind: "moon" })
                }
                return out
            }
            delegate: Item {
                required property var modelData
                visible: {
                    if (!root.inView(modelData.frac || 0, 0.01)) {
                        return false
                    }
                    var ix = root.mapX(modelData.frac || 0) * sky.width
                    var iy = sky.height - 2
                    return !root.pointInCutouts(ix, iy)
                }
                width: 7
                height: 5
                x: Math.round(root.mapX(modelData.frac || 0) * sky.width) - width / 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 0
                z: 2

                Canvas {
                    anchors.fill: parent
                    antialiasing: true
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.beginPath()
                        ctx.moveTo(0.5, 0.5)
                        ctx.lineTo(width / 2, height - 0.5)
                        ctx.lineTo(width - 0.5, 0.5)
                        ctx.strokeStyle = modelData.kind === "sun" ? root.sunStroke : root.moonStroke
                        ctx.lineWidth = 1.25
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.stroke()
                    }
                    Component.onCompleted: requestPaint()
                }
            }
        }

        // Sun icon on path
        Item {
            id: sunIcon
            visible: {
                if (!root.sunPoint.visible || !root.inView(root.sunPoint.xFrac, 0.02)) {
                    return false
                }
                var ix = root.mapX(root.sunPoint.xFrac) * sky.width
                var iy = sky.height - root.sunPoint.yNorm * root.peakSun
                return !root.pointInCutouts(ix, iy)
            }
            width: root.iconSize
            height: root.iconSize
            x: Math.round(root.mapX(root.sunPoint.xFrac) * sky.width) - width / 2
            y: Math.round(sky.height - root.sunPoint.yNorm * root.peakSun - height / 2) - 1
            z: 4
            rotation: 0

            NumberAnimation on rotation {
                from: 0
                to: 360
                duration: 48000
                loops: Animation.Infinite
                running: sunIcon.visible && root.visible
            }

            Canvas {
                id: sunIconCanvas
                anchors.fill: parent
                antialiasing: true
                onPaint: {
                    var ctx = getContext("2d")
                    var s = width
                    var cx = s / 2
                    var cy = s / 2
                    ctx.clearRect(0, 0, s, s)
                    ctx.strokeStyle = root.sunStroke
                    ctx.fillStyle = root.sunStroke
                    ctx.lineWidth = Math.max(1, s * 0.1)
                    ctx.lineCap = "round"
                    var i
                    for (i = 0; i < 8; i++) {
                        var a = i * Math.PI / 4
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(a) * s * 0.28, cy + Math.sin(a) * s * 0.28)
                        ctx.lineTo(cx + Math.cos(a) * s * 0.46, cy + Math.sin(a) * s * 0.46)
                        ctx.stroke()
                    }
                    ctx.beginPath()
                    ctx.arc(cx, cy, s * 0.2, 0, Math.PI * 2)
                    ctx.fill()
                }
                Component.onCompleted: requestPaint()
                Connections {
                    target: root
                    function onSunStrokeChanged() { sunIconCanvas.requestPaint() }
                }
            }
        }

        // Moon icon on path
        Item {
            id: moonIcon
            visible: {
                if (!root.moonPoint.visible || !root.inView(root.moonPoint.xFrac, 0.02)) {
                    return false
                }
                var ix = root.mapX(root.moonPoint.xFrac) * sky.width
                var iy = sky.height - root.moonPoint.yNorm * root.peakMoon
                return !root.pointInCutouts(ix, iy)
            }
            width: root.iconSize
            height: root.iconSize
            x: Math.round(root.mapX(root.moonPoint.xFrac) * sky.width) - width / 2
            y: Math.round(sky.height - root.moonPoint.yNorm * root.peakMoon - height / 2) - 1
            z: 4
            rotation: 0

            NumberAnimation on rotation {
                from: 0
                to: 360
                duration: 72000
                loops: Animation.Infinite
                running: moonIcon.visible && root.visible
            }

            Canvas {
                id: moonIconCanvas
                anchors.fill: parent
                antialiasing: true
                onPaint: {
                    var ctx = getContext("2d")
                    var s = width
                    var cx = s / 2
                    var cy = s / 2
                    var r = s * 0.36
                    ctx.clearRect(0, 0, s, s)
                    ctx.fillStyle = root.moonStroke
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.beginPath()
                    ctx.arc(cx + r * 0.38, cy - r * 0.08, r * 0.78, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.globalCompositeOperation = "source-over"
                }
                Component.onCompleted: requestPaint()
                Connections {
                    target: root
                    function onMoonStrokeChanged() { moonIconCanvas.requestPaint() }
                }
            }
        }
    }

    // —— Track ——
    // Layers (bottom → top): moon base → sun → business hours → activities.
    // Item.clip is axis-aligned only, so zoomed fills would square off the
    // capsule ends; OpacityMask keeps every layer rounded at any zoom.
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
            visible: false

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
                        return Qt.rgba(c.r, c.g, c.b, c.a * a)
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
                    Kirigami.Theme.highlightColor.r * 0.55 + 0.2,
                    Kirigami.Theme.highlightColor.g * 0.55 + 0.22,
                    Kirigami.Theme.highlightColor.b * 0.55 + 0.35,
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
                    color: Kirigami.Theme.textColor
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
                    color: segOvertime ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
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
        }

        GE.OpacityMask {
            anchors.fill: parent
            source: trackContent
            maskSource: trackMask
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
                root.strokeFadingGlow(ctx, x0, base, mid, ctrl, x1, base, root.workRibbon, glowW)
                root.strokeArcLine(ctx, x0, base, mid, ctrl, x1, base, root.workStroke, 1.15, [3, 2])
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
                    ctx.fillStyle = Qt.rgba(
                        Kirigami.Theme.backgroundColor.r,
                        Kirigami.Theme.backgroundColor.g,
                        Kirigami.Theme.backgroundColor.b, 0.94)
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
                    ctx.strokeStyle = Qt.rgba(
                        Kirigami.Theme.backgroundColor.r,
                        Kirigami.Theme.backgroundColor.g,
                        Kirigami.Theme.backgroundColor.b, 0.65)
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
            color: Kirigami.Theme.textColor
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: root.nowKnobSize
            height: root.nowKnobSize
            radius: width / 2
            color: Kirigami.Theme.textColor
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
                color: Kirigami.Theme.textColor
                opacity: 0.55
                font.pixelSize: Math.max(9, Kirigami.Theme.smallFont.pixelSize - 1)
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
